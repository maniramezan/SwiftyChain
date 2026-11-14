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
    /// must not interleave with another call.
    ///
    /// The timeout bounds a whole call, including the time spent waiting for an earlier
    /// call to finish: a call that can't start before its deadline throws
    /// ``KeychainError/timedOut`` without reaching libsecret, so callers queued behind
    /// an unanswered unlock prompt all fail within one timeout instead of one after
    /// another. Each call gets its own `GCancellable`, which a timer cancels at the
    /// deadline, so a hung keyring daemon can't block the caller forever.
    package final class SecretServiceClient: Sendable {
        /// Shared by every client, so `Keychain.shared`, other `Keychain` instances, and
        /// `KeychainStorage` wrappers in one process never interleave their calls.
        private static let callGate = DispatchSemaphore(value: 1)

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

        /// Changes the label or secret of every item matching the query, in whichever
        /// collection holds it, keeping each item's own attributes.
        ///
        /// A `nil` label or secret leaves that part of each item unchanged. Every match is
        /// read, which unlocks the keyring if needed, before anything is written. The
        /// Secret Service has no transactions, so when a write fails part-way through,
        /// the items already changed are restored, as far as the keyring still responds,
        /// to their previous label and secret before the error is thrown. The search and the writes run under one lock and
        /// one deadline.
        ///
        /// - Throws: ``KeychainError/itemNotFound`` when nothing matches, and
        ///   ``KeychainError/userPresenceRequired`` when a match stays locked.
        package func replace(_ matching: SecretServiceItemQuery, label: String?, data: Data?) throws {
            try Self.validate(matching, label: label)
            try perform("replace", schema: matching.schema) { cancellable, _ in
                try withAttributes(matching.attributes) { attributes in
                    try withSearchResults(
                        matching,
                        attributes: attributes,
                        unlock: true,
                        loadSecrets: true,
                        cancellable: cancellable
                    ) { handles in
                        guard !handles.isEmpty else {
                            throw KeychainError.itemNotFound
                        }
                        var originals: [StoredItem] = []
                        for handle in handles {
                            guard
                                let item = try readItem(
                                    handle,
                                    schema: matching.schema,
                                    loadSecret: true,
                                    cancellable: cancellable
                                )
                            else {
                                continue
                            }
                            guard let secret = item.secret else {
                                SwiftyChainLoggers.backend.debug(
                                    "Secret Service update found a match that stays locked")
                                throw KeychainError.userPresenceRequired
                            }
                            originals.append(StoredItem(handle: handle, item: item, secret: secret))
                        }
                        guard !originals.isEmpty else {
                            throw KeychainError.itemNotFound
                        }

                        // An item is recorded before its write, because a write that changes
                        // both the secret and the label can fail after changing only one.
                        var written: [StoredItem] = []
                        do {
                            for original in originals {
                                written.append(original)
                                try rewrite(
                                    original,
                                    schema: matching.schema,
                                    label: label,
                                    data: data,
                                    cancellable: cancellable
                                )
                            }
                        } catch {
                            restore(written, schema: matching.schema, cancellable: cancellable)
                            throw error
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
        ///
        /// Another process may delete a match between libsecret's search and its delete,
        /// which libsecret reports as "no such object". That item is gone either way, so
        /// the clear is retried for the remaining matches rather than reported as
        /// ``KeychainError/itemNotFound``.
        @discardableResult
        package func clear(_ query: SecretServiceItemQuery) throws -> Bool {
            try Self.validate(query, label: nil)
            return try perform("clear", schema: query.schema) { cancellable, _ in
                try withAttributes(query.attributes) { attributes in
                    var removed = false
                    for _ in 0..<Self.clearAttempts {
                        guard
                            try hasMatchingItems(query, attributes: attributes, unlock: true, cancellable: cancellable)
                        else {
                            return removed
                        }
                        var error: OpaquePointer?
                        let cleared = swiftychain_secret_clear(query.schema.kind, attributes, cancellable, &error)
                        do {
                            try throwIfFailed(error)
                            removed = removed || cleared != 0
                            break
                        } catch let failure as SecretServiceFailure where SecretServiceErrors.isNoSuchObject(failure) {
                            SwiftyChainLoggers.backend.debug("libsecret clear raced a concurrent delete; retrying")
                            removed = true
                        }
                    }
                    if try hasMatchingItems(query, attributes: attributes, unlock: false, cancellable: cancellable) {
                        throw KeychainError.userPresenceRequired
                    }
                    return removed
                }
            }
        }

        /// How many times ``clear(_:)`` retries after a match disappears mid-delete.
        private static let clearAttempts = 3

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
            try withSearchResults(
                query,
                attributes: attributes,
                unlock: unlock,
                loadSecrets: loadSecrets,
                cancellable: cancellable
            ) { handles in
                try handles.compactMap { handle in
                    try readItem(handle, schema: query.schema, loadSecret: loadSecrets, cancellable: cancellable)
                }
            }
        }

        /// Runs `body` with the matching items' libsecret handles, which stay valid until
        /// it returns.
        private func withSearchResults<Result>(
            _ query: SecretServiceItemQuery,
            attributes: OpaquePointer,
            unlock: Bool,
            loadSecrets: Bool,
            cancellable: OpaquePointer?,
            _ body: ([OpaquePointer]) throws -> Result
        ) throws -> Result {
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
            defer {
                if let list {
                    swiftychain_secret_list_free(list)
                }
            }

            var handles: [OpaquePointer] = []
            var node = list
            while let current = node {
                if let item = swiftychain_secret_list_item(current) {
                    handles.append(item)
                }
                node = swiftychain_secret_list_next(current)
            }
            return try body(handles)
        }

        /// Writes a new label or secret to one item found by ``replace(_:label:data:)``.
        private func rewrite(
            _ stored: StoredItem,
            schema: SecretServiceSchema,
            label: String?,
            data: Data?,
            cancellable: OpaquePointer?
        ) throws {
            guard swiftychain_secret_item_is_service_item(stored.handle) != 0 else {
                // libsecret's file backend has one collection, so storing with the item's
                // exact attribute set replaces it there.
                try withAttributes(stored.item.attributes) { attributes in
                    try storeItem(
                        schema,
                        attributes: attributes,
                        label: label ?? stored.item.label,
                        data: data ?? stored.secret,
                        cancellable: cancellable
                    )
                }
                return
            }
            if let data {
                var error: OpaquePointer?
                let written = data.withUnsafeBytes { buffer in
                    swiftychain_secret_item_set_secret(
                        stored.handle,
                        buffer.baseAddress,
                        buffer.count,
                        cancellable,
                        &error
                    )
                }
                try throwIfFailed(error)
                if written == 0 {
                    SwiftyChainLoggers.backend.error("libsecret set_secret reported failure without an error")
                    throw KeychainError.operationFailed(0)
                }
            }
            if let label, label != stored.item.label {
                var error: OpaquePointer?
                let written = swiftychain_secret_item_set_label(stored.handle, label, cancellable, &error)
                try throwIfFailed(error)
                if written == 0 {
                    SwiftyChainLoggers.backend.error("libsecret set_label reported failure without an error")
                    throw KeychainError.operationFailed(0)
                }
            }
        }

        /// Puts back the label and secret of items changed by a ``replace(_:label:data:)``
        /// that failed part-way through. Best effort: a failure is logged, and the
        /// original error is what the caller sees.
        private func restore(_ items: [StoredItem], schema: SecretServiceSchema, cancellable: OpaquePointer?) {
            guard !items.isEmpty else { return }
            SwiftyChainLoggers.backend.info(
                "Restoring \(items.count, privacy: .public) Secret Service items after a failed update"
            )
            for stored in items.reversed() {
                do {
                    try rewrite(
                        stored, schema: schema, label: stored.item.label, data: stored.secret, cancellable: cancellable)
                } catch {
                    SwiftyChainLoggers.backend.error(
                        "Could not restore a Secret Service item after a failed update for schema=\(schema.name, privacy: .public)"
                    )
                }
            }
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
            // The deadline is fixed before waiting for the gate, so the timeout covers the
            // wait as well as the call.
            let deadline = SecretServiceDeadline.dispatchTime(after: timeout)
            guard Self.callGate.wait(timeout: deadline) == .success else {
                SwiftyChainLoggers.backend.debug(
                    "libsecret \(operation, privacy: .public) timed out waiting for an earlier call for schema=\(schema.name, privacy: .public)"
                )
                throw KeychainError.timedOut
            }
            defer { Self.callGate.signal() }

            // The library must load before anything below it, because every GLib and
            // libsecret call dereferences symbols resolved by dlopen. Then the timer is
            // created, so every GLib call after it — including the D-Bus session handshake
            // in `ensureSessionBus` — respects the deadline.
            try ensureLibraryLoaded()
            let timer = TimeoutTimer(deadline: deadline)
            defer { timer.disarm() }
            do {
                try ensureSessionBus(timer: timer)
                SwiftyChainLoggers.backend.debug(
                    "libsecret \(operation, privacy: .public) started for schema=\(schema.name, privacy: .public)"
                )
                var error: OpaquePointer?
                let result: Result
                do {
                    result = try body(timer.cancellable, &error)
                } catch let failure as SecretServiceFailure
                    where SecretServiceErrors.isStaleConnection(failure) && !timer.fired
                {
                    // A restarted keyring daemon leaves libsecret's cached proxy pointing
                    // at the old process, so the request was never delivered. Reconnect
                    // and try once more; a provider that is really gone fails again.
                    SwiftyChainLoggers.backend.info(
                        "libsecret \(operation, privacy: .public) found a stale connection code=\(failure.code, privacy: .public); reconnecting"
                    )
                    swiftychain_secret_service_reset()
                    error = nil
                    result = try body(timer.cancellable, &error)
                }
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
                resetConnectionIfNeeded(after: keychainError)
                throw keychainError
            } catch let keychainError as KeychainError {
                resetConnectionIfNeeded(after: keychainError)
                throw keychainError
            }
        }

        /// Drops libsecret's cached connection after a failure that may mean the keyring
        /// daemon or the bus restarted, so a long-running process recovers on its next
        /// call instead of failing until it restarts.
        private func resetConnectionIfNeeded(after error: KeychainError) {
            guard SecretServiceErrors.shouldResetConnection(after: error) else { return }
            SwiftyChainLoggers.backend.debug(
                "Resetting the Secret Service connection after error=\(error.logName, privacy: .public)"
            )
            swiftychain_secret_service_reset()
        }

        private func ensureLibraryLoaded() throws {
            switch swiftychain_secret_load() {
            case SWIFTYCHAIN_SECRET_LOADED:
                break
            case SWIFTYCHAIN_SECRET_SYMBOL_MISSING:
                SwiftyChainLoggers.backend.debug("libsecret is missing required symbols")
                throw SecretServiceUnavailability.libraryTooOld.error
            case SWIFTYCHAIN_SECRET_DYNAMIC_LOADING_UNAVAILABLE:
                SwiftyChainLoggers.backend.debug("This statically linked binary can't load libsecret-1.so.0")
                throw SecretServiceUnavailability.dynamicLoadingUnavailable.error
            default:
                SwiftyChainLoggers.backend.debug("libsecret-1.so.0 could not be loaded")
                throw SecretServiceUnavailability.libraryMissing.error
            }
        }

        private func ensureSessionBus(timer: TimeoutTimer) throws {
            var error: OpaquePointer?
            guard swiftychain_secret_session_bus_available(timer.cancellable, &error) == 0 else { return }
            var failure: SecretServiceFailure?
            if let error {
                let domain = swiftychain_secret_error_domain(error).map { String(cString: $0) } ?? "unknown"
                failure = SecretServiceFailure(domain: domain, code: swiftychain_secret_error_code(error))
                swiftychain_secret_error_free(error)
            }
            let keychainError = SecretServiceErrors.sessionBusError(for: failure, timerFired: timer.fired)
            SwiftyChainLoggers.backend.debug(
                "Could not connect to the D-Bus session bus error=\(keychainError.logName, privacy: .public)"
            )
            throw keychainError
        }

        private func readItem(
            _ item: OpaquePointer,
            schema: SecretServiceSchema,
            loadSecret: Bool,
            cancellable: OpaquePointer?
        ) throws -> SecretServiceItem? {
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
                do {
                    try throwIfFailed(error)
                } catch let failure as SecretServiceFailure where SecretServiceErrors.isNoSuchObject(failure) {
                    // Another process deleted the item after the search found it.
                    SwiftyChainLoggers.backend.debug("A Secret Service item disappeared while being read")
                    return nil
                }
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

    /// One item found by ``SecretServiceClient/replace(_:label:data:)``, with the label
    /// and secret it had before the update.
    private struct StoredItem {
        let handle: OpaquePointer
        let item: SecretServiceItem
        let secret: Data
    }

    /// Cancels a `GCancellable` at a deadline, unless disarmed first.
    ///
    /// Disarming cancels the dispatch timer, which releases its handler right away, so a
    /// finished call doesn't keep its timer and `GCancellable` alive until the deadline.
    private final class TimeoutTimer {
        private let state: TimeoutState
        private let source: any DispatchSourceTimer

        var cancellable: OpaquePointer? { state.cancellable }
        var fired: Bool { state.fired.load(ordering: .acquiring) }

        init(deadline: DispatchTime) {
            let state = TimeoutState()
            self.state = state
            source = DispatchSource.makeTimerSource(queue: .global())
            source.setEventHandler {
                state.fired.store(true, ordering: .releasing)
                if let cancellable = state.cancellable {
                    swiftychain_secret_cancellable_cancel(cancellable)
                }
            }
            source.schedule(deadline: deadline)
            source.resume()
        }

        func disarm() {
            source.cancel()
        }
    }

    /// The `GCancellable` a ``TimeoutTimer`` cancels. The timer's handler holds it, so it
    /// is freed only after both the call and any in-flight cancel are done with it.
    // `@unchecked Sendable`: GCancellable is documented as thread-safe, and `fired` is
    // atomic.
    private final class TimeoutState: @unchecked Sendable {
        let cancellable: OpaquePointer?
        let fired = Atomic(false)

        init() {
            cancellable = swiftychain_secret_cancellable_new()
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
