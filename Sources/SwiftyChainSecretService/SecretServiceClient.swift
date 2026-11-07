#if os(Linux)
    import CSwiftyChainSecret
    import Dispatch
    import Foundation
    import Synchronization
    import SwiftyChainCore

    /// An item returned by a Secret Service search.
    package struct SecretServiceItem: Sendable {
        package let attributes: [String: String]
        package let label: String
        package let secret: Data?
    }

    /// A thin, memory-safe wrapper over the dlopen-based libsecret loader.
    ///
    /// Calls are serialized process-wide, across every client instance, because
    /// libsecret's synchronous API runs a nested main loop on the calling thread and
    /// because SwiftyChain's check-then-write operations, such as ``add(_:label:data:)``,
    /// must not interleave with another call. Each call gets its own `GCancellable`,
    /// which a timer cancels once the configured timeout elapses, so a hung keyring
    /// daemon or an unanswered unlock prompt can't block the caller forever.
    package final class SecretServiceClient: Sendable {
        /// Shared by every client, so `Keychain.shared`, other `Keychain` instances, and
        /// `KeychainStorage` wrappers in one process never interleave their calls.
        private static let callLock = Mutex(())

        private let timeout: Duration

        package init(timeout: Duration) {
            self.timeout = timeout
        }

        /// Stores a new item, failing with ``KeychainError/duplicateItem`` when one with
        /// the same identity exists. The check and the write run under one lock and one
        /// deadline, so concurrent adds in this process can't both succeed.
        package func add(_ identity: SecretServiceItemQuery, label: String, data: Data) throws {
            try Self.validate(identity, label: label)
            try perform("add", schema: identity.schema) { cancellable, _ in
                try withAttributes(identity.attributes) { attributes in
                    if try hasMatchingItems(identity, attributes: attributes, unlock: false, cancellable: cancellable) {
                        SwiftyChainLoggers.backend.debug("Secret Service add found an existing item")
                        throw KeychainError.duplicateItem
                    }
                    try storeItem(
                        identity.schema,
                        attributes: attributes,
                        label: label,
                        data: data,
                        cancellable: cancellable
                    )
                }
            }
        }

        /// Rewrites every item matching the query, keeping each item's own attributes.
        ///
        /// When `data` is `nil`, each item keeps its current secret, which means the
        /// keyring may need to be unlocked to read it. The search and the writes run under
        /// one lock and one deadline.
        ///
        /// - Throws: ``KeychainError/itemNotFound`` when nothing matches.
        package func replace(_ matching: SecretServiceItemQuery, label: String?, data: Data?) throws {
            try Self.validate(matching, label: label)
            try perform("replace", schema: matching.schema) { cancellable, _ in
                try withAttributes(matching.attributes) { attributes in
                    let needsSecrets = data == nil
                    let items = try searchItems(
                        matching,
                        attributes: attributes,
                        unlock: needsSecrets,
                        loadSecrets: needsSecrets,
                        cancellable: cancellable
                    )
                    guard !items.isEmpty else {
                        throw KeychainError.itemNotFound
                    }
                    for item in items {
                        guard let secret = data ?? item.secret else {
                            SwiftyChainLoggers.backend.error("Secret Service update could not read the existing secret")
                            throw KeychainError.unexpectedData
                        }
                        // Storing with the item's exact attribute set replaces that item in place.
                        let itemQuery = SecretServiceItemQuery(schema: matching.schema, attributes: item.attributes)
                        try withAttributes(itemQuery.attributes) { itemAttributes in
                            try storeItem(
                                matching.schema,
                                attributes: itemAttributes,
                                label: label ?? item.label,
                                data: secret,
                                cancellable: cancellable
                            )
                        }
                    }
                }
            }
        }

        /// Returns the secret of the first matching item, or `nil` when nothing matches.
        package func lookup(_ query: SecretServiceItemQuery) throws -> Data? {
            try Self.validate(query, label: nil)
            return try perform("lookup", schema: query.schema) { cancellable, error in
                try withAttributes(query.attributes) { attributes in
                    let value = swiftychain_secret_lookup(query.schema.kind, attributes, cancellable, &error)
                    try throwIfFailed(error)
                    guard let value else {
                        if try hasMatchingItems(query, attributes: attributes, unlock: false, cancellable: cancellable)
                        {
                            throw KeychainError.userPresenceRequired
                        }
                        return nil
                    }
                    defer { swiftychain_secret_value_free(value) }
                    return copySecret(value)
                }
            }
        }

        /// Returns every matching item. The keyring is asked to unlock only when secrets
        /// are loaded, because item attributes are readable while it is locked.
        package func search(_ query: SecretServiceItemQuery, loadSecrets: Bool) throws -> [SecretServiceItem] {
            try Self.validate(query, label: nil)
            return try perform("search", schema: query.schema) { cancellable, _ in
                try withAttributes(query.attributes) { attributes in
                    try searchItems(
                        query,
                        attributes: attributes,
                        unlock: loadSecrets,
                        loadSecrets: loadSecrets,
                        cancellable: cancellable
                    )
                }
            }
        }

        /// Removes every matching item. Returns whether anything was removed.
        @discardableResult
        package func clear(_ query: SecretServiceItemQuery) throws -> Bool {
            try Self.validate(query, label: nil)
            return try perform("clear", schema: query.schema) { cancellable, error in
                try withAttributes(query.attributes) { attributes in
                    guard try hasMatchingItems(query, attributes: attributes, unlock: true, cancellable: cancellable)
                    else {
                        return false
                    }
                    let removed = swiftychain_secret_clear(query.schema.kind, attributes, cancellable, &error)
                    try throwIfFailed(error)
                    if try hasMatchingItems(query, attributes: attributes, unlock: false, cancellable: cancellable) {
                        throw KeychainError.userPresenceRequired
                    }
                    return removed != 0
                }
            }
        }

        /// Rejects strings libsecret would silently truncate. Swift passes strings to C
        /// as `const char *`, so libsecret sees only the text before the first NUL, and
        /// `"x\0alpha"` and `"x\0beta"` would select the same item.
        private static func validate(_ query: SecretServiceItemQuery, label: String?) throws {
            for (name, value) in query.attributes where value.utf8.contains(0) {
                SwiftyChainLoggers.backend.debug(
                    "Rejected a Secret Service attribute containing NUL for attribute=\(name, privacy: .public)"
                )
                throw KeychainError.platformUnsupported("Secret Service attributes cannot contain NUL characters")
            }
            if let label, label.utf8.contains(0) {
                SwiftyChainLoggers.backend.debug("Rejected a Secret Service label containing NUL")
                throw KeychainError.platformUnsupported("Secret Service labels cannot contain NUL characters")
            }
        }

        private func storeItem(
            _ schema: SecretServiceSchema,
            attributes: OpaquePointer,
            label: String,
            data: Data,
            cancellable: OpaquePointer?
        ) throws {
            var error: OpaquePointer?
            let stored = data.withUnsafeBytes { buffer in
                swiftychain_secret_store(
                    schema.kind,
                    attributes,
                    label,
                    buffer.baseAddress,
                    buffer.count,
                    cancellable,
                    &error
                )
            }
            if stored == 0 {
                do {
                    try throwIfFailed(error)
                } catch let failure as SecretServiceFailure where SecretServiceErrors.isNoSuchObject(failure) {
                    // A store targets the default collection, so "no such object" means the
                    // provider has none, as with KeePassXC before a database is exposed.
                    SwiftyChainLoggers.backend.debug("libsecret store found no default collection")
                    throw SecretServiceUnavailability.noDefaultCollection.error
                }
                SwiftyChainLoggers.backend.error("libsecret store reported failure without an error")
                throw KeychainError.operationFailed(0)
            }
        }

        private func searchItems(
            _ query: SecretServiceItemQuery,
            attributes: OpaquePointer,
            unlock: Bool,
            loadSecrets: Bool,
            cancellable: OpaquePointer?
        ) throws -> [SecretServiceItem] {
            var error: OpaquePointer?
            let list = swiftychain_secret_search(
                query.schema.kind,
                attributes,
                unlock ? 1 : 0,
                loadSecrets ? 1 : 0,
                cancellable,
                &error
            )
            try throwIfFailed(error)
            guard let list else { return [] }
            defer { swiftychain_secret_list_free(list) }

            var items: [SecretServiceItem] = []
            var node: OpaquePointer? = list
            while let current = node {
                if let item = swiftychain_secret_list_item(current) {
                    items.append(
                        try readItem(
                            item,
                            schema: query.schema,
                            loadSecret: loadSecrets,
                            cancellable: cancellable
                        )
                    )
                }
                node = swiftychain_secret_list_next(current)
            }
            return items
        }

        private func hasMatchingItems(
            _ query: SecretServiceItemQuery,
            attributes: OpaquePointer,
            unlock: Bool,
            cancellable: OpaquePointer?
        ) throws -> Bool {
            var error: OpaquePointer?
            let items = swiftychain_secret_search(query.schema.kind, attributes, unlock ? 1 : 0, 0, cancellable, &error)
            defer {
                if let items {
                    swiftychain_secret_list_free(items)
                }
            }
            try throwIfFailed(error)
            return items != nil
        }

        private func perform<Result: Sendable>(
            _ operation: String,
            schema: SecretServiceSchema,
            _ body: (OpaquePointer?, inout OpaquePointer?) throws -> Result
        ) throws -> Result {
            try Self.callLock.withLock { _ in
                // The library must load before anything below it, because every GLib and
                // libsecret call dereferences symbols resolved by dlopen. Then the timer
                // is created, so every GLib call after it — including the D-Bus
                // session-handshake in `ensureSessionBus` — respects the timeout.
                try ensureLibraryLoaded()
                let timer = TimeoutTimer(after: timeout)
                defer { timer.disarm() }
                try ensureSessionBus(cancellable: timer.cancellable)
                SwiftyChainLoggers.backend.debug(
                    "libsecret \(operation, privacy: .public) started for schema=\(schema.name, privacy: .public)"
                )
                var error: OpaquePointer?
                do {
                    let result = try body(timer.cancellable, &error)
                    SwiftyChainLoggers.backend.debug(
                        "libsecret \(operation, privacy: .public) succeeded for schema=\(schema.name, privacy: .public)"
                    )
                    return result
                } catch let failure as SecretServiceFailure {
                    let keychainError = SecretServiceErrors.keychainError(for: failure, timerFired: timer.fired)
                    if keychainError.isExpectedOutcome {
                        SwiftyChainLoggers.backend.debug(
                            "libsecret \(operation, privacy: .public) failed domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public) error=\(keychainError.logName, privacy: .public)"
                        )
                    } else {
                        SwiftyChainLoggers.backend.error(
                            "libsecret \(operation, privacy: .public) failed domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public) error=\(keychainError.logName, privacy: .public)"
                        )
                    }
                    throw keychainError
                }
            }
        }

        private func ensureLibraryLoaded() throws {
            switch swiftychain_secret_load() {
            case SWIFTYCHAIN_SECRET_LOADED:
                break
            case SWIFTYCHAIN_SECRET_SYMBOL_MISSING:
                SwiftyChainLoggers.backend.debug("libsecret is missing required symbols")
                throw SecretServiceUnavailability.libraryTooOld.error
            default:
                SwiftyChainLoggers.backend.debug("libsecret-1.so.0 could not be loaded")
                throw SecretServiceUnavailability.libraryMissing.error
            }
        }

        private func ensureSessionBus(cancellable: OpaquePointer?) throws {
            var error: OpaquePointer?
            if swiftychain_secret_session_bus_available(cancellable, &error) == 0 {
                if let error {
                    swiftychain_secret_error_free(error)
                }
                SwiftyChainLoggers.backend.debug("No D-Bus session bus is available")
                throw SecretServiceUnavailability.noSessionBus.error
            }
        }

        private func readItem(
            _ item: OpaquePointer,
            schema: SecretServiceSchema,
            loadSecret: Bool,
            cancellable: OpaquePointer?
        ) throws -> SecretServiceItem {
            var attributes: [String: String] = [:]
            if let table = swiftychain_secret_item_attributes(item) {
                defer { swiftychain_secret_attributes_free(table) }
                for name in schema.attributeNames {
                    if let value = swiftychain_secret_attributes_lookup(table, name) {
                        attributes[name] = String(cString: value)
                    }
                }
            }

            var label = ""
            if let rawLabel = swiftychain_secret_item_label(item) {
                label = String(cString: rawLabel)
                swiftychain_secret_string_free(rawLabel)
            }

            var secret: Data?
            if loadSecret {
                var error: OpaquePointer?
                let value = swiftychain_secret_item_secret(item, cancellable, &error)
                try throwIfFailed(error)
                if let value {
                    secret = copySecret(value)
                    swiftychain_secret_value_free(value)
                }
            }
            return SecretServiceItem(attributes: attributes, label: label, secret: secret)
        }

        private func withAttributes<Result>(
            _ values: [String: String],
            _ body: (OpaquePointer) throws -> Result
        ) throws -> Result {
            guard let table = swiftychain_secret_attributes_new() else {
                SwiftyChainLoggers.backend.error("libsecret failed to allocate an attribute table")
                throw KeychainError.operationFailed(0)
            }
            defer { swiftychain_secret_attributes_free(table) }
            for (key, value) in values {
                swiftychain_secret_attributes_insert(table, key, value)
            }
            return try body(table)
        }

        private func copySecret(_ value: OpaquePointer) -> Data {
            var length = 0
            guard let bytes = swiftychain_secret_value_bytes(value, &length) else {
                return Data()
            }
            return Data(bytes: bytes, count: length)
        }

        private func throwIfFailed(_ error: OpaquePointer?) throws {
            guard let error else { return }
            defer { swiftychain_secret_error_free(error) }
            let domain = swiftychain_secret_error_domain(error).map { String(cString: $0) } ?? "unknown"
            throw SecretServiceFailure(domain: domain, code: swiftychain_secret_error_code(error))
        }
    }

    /// Cancels a `GCancellable` when the timeout elapses, unless disarmed first.
    // `@unchecked Sendable`: GCancellable is documented as thread-safe. The fire block
    // retains the timer until it has finished cancelling, so `deinit` can never free
    // the cancellable while a concurrent cancel still references it, and `workItem` is
    // touched only by the thread that owns the timer.
    private final class TimeoutTimer: @unchecked Sendable {
        let cancellable: OpaquePointer?
        private let didFire = Atomic(false)
        private var workItem: DispatchWorkItem?

        var fired: Bool { didFire.load(ordering: .acquiring) }

        init(after timeout: Duration) {
            cancellable = swiftychain_secret_cancellable_new()
            let components = timeout.components
            let nanoseconds = components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
            let workItem = DispatchWorkItem {
                self.didFire.store(true, ordering: .releasing)
                if let cancellable = self.cancellable {
                    swiftychain_secret_cancellable_cancel(cancellable)
                }
            }
            self.workItem = workItem
            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds)), execute: workItem)
        }

        func disarm() {
            workItem?.cancel()
            workItem = nil
        }

        deinit {
            if let cancellable {
                swiftychain_secret_cancellable_free(cancellable)
            }
        }
    }

    extension SecretServiceSchema {
        fileprivate var kind: swiftychain_secret_schema_kind {
            switch self {
            case .genericPassword: SWIFTYCHAIN_SECRET_GENERIC_PASSWORD
            case .internetPassword: SWIFTYCHAIN_SECRET_INTERNET_PASSWORD
            }
        }
    }

    extension SecretServiceFailure: Error {}
#endif
