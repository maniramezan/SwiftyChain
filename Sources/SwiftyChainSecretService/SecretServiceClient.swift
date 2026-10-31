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
    /// Calls are serialized because libsecret's synchronous API runs a nested main loop
    /// on the calling thread. Each call gets its own `GCancellable`, which a timer cancels
    /// once the configured timeout elapses, so a hung keyring daemon or an unanswered
    /// unlock prompt can't block the caller forever.
    package final class SecretServiceClient: Sendable {
        private let timeout: Duration
        private let callLock = Mutex(())

        package init(timeout: Duration) {
            self.timeout = timeout
        }

        package func store(_ query: SecretServiceItemQuery, label: String, data: Data) throws {
            try perform("store", schema: query.schema) { cancellable, error in
                try withAttributes(query.attributes) { attributes in
                    let stored = data.withUnsafeBytes { buffer in
                        swiftychain_secret_store(
                            query.schema.kind,
                            attributes,
                            label,
                            buffer.baseAddress,
                            buffer.count,
                            cancellable,
                            &error
                        )
                    }
                    if stored == 0 {
                        try throwIfFailed(error)
                        SwiftyChainLoggers.backend.error("libsecret store reported failure without an error")
                        throw KeychainError.operationFailed(0)
                    }
                }
            }
        }

        /// Returns the secret of the first matching item, or `nil` when nothing matches.
        package func lookup(_ query: SecretServiceItemQuery) throws -> Data? {
            try perform("lookup", schema: query.schema) { cancellable, error in
                try withAttributes(query.attributes) { attributes in
                    let value = swiftychain_secret_lookup(query.schema.kind, attributes, cancellable, &error)
                    try throwIfFailed(error)
                    guard let value else { return nil }
                    defer { swiftychain_secret_value_free(value) }
                    return copySecret(value)
                }
            }
        }

        package func search(_ query: SecretServiceItemQuery, loadSecrets: Bool) throws -> [SecretServiceItem] {
            try perform("search", schema: query.schema) { cancellable, error in
                try withAttributes(query.attributes) { attributes in
                    let list = swiftychain_secret_search(
                        query.schema.kind,
                        attributes,
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
            }
        }

        /// Removes every matching item. Returns whether anything was removed.
        @discardableResult
        package func clear(_ query: SecretServiceItemQuery) throws -> Bool {
            try perform("clear", schema: query.schema) { cancellable, error in
                try withAttributes(query.attributes) { attributes in
                    let removed = swiftychain_secret_clear(query.schema.kind, attributes, cancellable, &error)
                    try throwIfFailed(error)
                    return removed != 0
                }
            }
        }

        private func perform<Result: Sendable>(
            _ operation: String,
            schema: SecretServiceSchema,
            _ body: (OpaquePointer?, inout OpaquePointer?) throws -> Result
        ) throws -> Result {
            try callLock.withLock { _ in
                try ensureAvailable()
                SwiftyChainLoggers.backend.debug(
                    "libsecret \(operation, privacy: .public) started for schema=\(schema.name, privacy: .public)"
                )
                let timer = TimeoutTimer(after: timeout)
                defer { timer.disarm() }
                var error: OpaquePointer?
                do {
                    let result = try body(timer.cancellable, &error)
                    SwiftyChainLoggers.backend.debug(
                        "libsecret \(operation, privacy: .public) succeeded for schema=\(schema.name, privacy: .public)"
                    )
                    return result
                } catch let failure as SecretServiceFailure {
                    let keychainError = SecretServiceErrors.keychainError(for: failure, timerFired: timer.fired)
                    SwiftyChainLoggers.backend.error(
                        "libsecret \(operation, privacy: .public) failed domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public) error=\(keychainError.logName, privacy: .public)"
                    )
                    throw keychainError
                }
            }
        }

        private func ensureAvailable() throws {
            switch swiftychain_secret_load() {
            case SWIFTYCHAIN_SECRET_LOADED:
                break
            case SWIFTYCHAIN_SECRET_SYMBOL_MISSING:
                SwiftyChainLoggers.backend.error("libsecret is missing required symbols")
                throw SecretServiceUnavailability.libraryTooOld.error
            default:
                SwiftyChainLoggers.backend.error("libsecret-1.so.0 could not be loaded")
                throw SecretServiceUnavailability.libraryMissing.error
            }
            var error: OpaquePointer?
            if swiftychain_secret_session_bus_available(&error) == 0 {
                if let error {
                    swiftychain_secret_error_free(error)
                }
                SwiftyChainLoggers.backend.error("No D-Bus session bus is available")
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
    // `@unchecked Sendable`: GCancellable is documented as thread-safe, the pointer is
    // released only in deinit, and `workItem` is touched only by the thread that owns the timer.
    private final class TimeoutTimer: @unchecked Sendable {
        let cancellable: OpaquePointer?
        private let didFire = Atomic(false)
        private var workItem: DispatchWorkItem?

        var fired: Bool { didFire.load(ordering: .acquiring) }

        init(after timeout: Duration) {
            cancellable = swiftychain_secret_cancellable_new()
            let components = timeout.components
            let nanoseconds = components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                didFire.store(true, ordering: .releasing)
                if let cancellable {
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
