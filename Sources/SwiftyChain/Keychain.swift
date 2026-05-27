import Foundation
import OSLog

/// Actor-isolated public API for keychain operations.
///
/// ``Keychain`` provides a type-safe interface for storing, loading, updating,
/// and deleting items in the system keychain. All mutations are serialized through
/// Swift's actor model, making it safe to call from any concurrency context.
///
/// ## Getting started
///
/// Use the shared singleton for most use cases:
///
/// ```swift
/// let keychain = Keychain.shared
/// ```
///
/// ## Saving and loading values
///
/// Define a typed key, then store and retrieve values:
///
/// ```swift
/// let key = KeychainKey<String>(service: "com.example.app", account: "auth-token")
/// try await Keychain.shared.save("my-token", for: key)
/// let token = try await Keychain.shared.load(key: key)
/// ```
///
/// ## Observing changes
///
/// When built with the `Observation` trait, you can receive async events for each mutation:
///
/// ```swift
/// import OSLog
///
/// let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")
///
/// for await event in await Keychain.shared.observeKeychainChanges(service: "com.example.app") {
///     logger.debug("Observed change: \(String(describing: event.kind), privacy: .public)")
/// }
/// ```
public actor Keychain: KeychainProtocol {
    /// The shared keychain instance backed by the system Apple Keychain.
    public static let shared = Keychain()

    private enum MutationKind: Sendable {
        case saved
        case updated
        case deleted
        case bulkDeleted
    }

    internal let backend: any SecureStorageBackend
    #if Observation
        private var observers: [UUID: Observer] = [:]
    #endif

    /// Creates a new ``Keychain`` instance backed by the system Apple Keychain.
    public init() {
        self.backend = AppleKeychainBackend()
    }

    internal init(backend: any SecureStorageBackend) {
        self.backend = backend
    }

    /// Saves a value to the keychain for the given key.
    ///
    /// Fails with ``KeychainError/duplicateItem`` if an item already exists for the key.
    /// Use ``upsert(_:for:)`` to save or overwrite transparently.
    ///
    /// - Parameters:
    ///   - value: The value to persist.
    ///   - key: The ``KeychainKey`` that identifies the item.
    /// - Throws: ``KeychainError/duplicateItem`` if an item already exists,
    ///   or another ``KeychainError`` if the underlying operation fails.
    ///
    /// ```swift
    /// let key = KeychainKey<String>(service: "com.example.app", account: "token")
    /// try await Keychain.shared.save("abc123", for: key)
    /// ```
    public func save<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        logKeychainOperationStarted("save", service: key.service, account: key.account)
        do {
            try backend.add(addQuery(for: key), data: value.keychainData())
            notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .saved)
            logKeychainOperationSucceeded("save", service: key.service, account: key.account)
        } catch {
            logKeychainOperationFailed("save", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    /// Loads a value from the keychain for the given key.
    ///
    /// - Parameter key: The ``KeychainKey`` that identifies the item.
    /// - Returns: The stored value decoded as `T`.
    /// - Throws: ``KeychainError/itemNotFound`` if no item exists for the key,
    ///   or another ``KeychainError`` on decode failure.
    ///
    /// ```swift
    /// let token = try await Keychain.shared.load(key: key)
    /// ```
    public func load<T: KeychainStorable>(key: KeychainKey<T>) throws -> T {
        logKeychainOperationStarted("load", service: key.service, account: key.account)
        do {
            let result = try backend.copyMatching(identityQuery(for: key, returnData: true))
            guard case .data(let data) = result else {
                SwiftyChainLoggers.keychain.error(
                    "load returned unexpected result for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
                )
                throw KeychainError.unexpectedData
            }
            return try T.fromKeychainData(data)
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "load returned item not found for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            throw KeychainError.itemNotFound
        } catch {
            logKeychainOperationFailed("load", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    /// Loads a value from the keychain, returning `nil` when the item does not exist.
    ///
    /// Unlike ``load(key:)``, this method swallows ``KeychainError/itemNotFound``
    /// and returns `nil` instead of throwing.
    ///
    /// - Parameter key: The ``KeychainKey`` that identifies the item.
    /// - Returns: The stored value, or `nil` if the item does not exist.
    /// - Throws: ``KeychainError`` for failures other than item not found.
    ///
    /// ```swift
    /// if let token = try await Keychain.shared.loadIfPresent(key: key) {
    ///     // use token
    /// }
    /// ```
    public func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T? {
        do {
            return try load(key: key)
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "loadIfPresent returned nil for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            return nil
        }
    }

    /// Updates an existing keychain item.
    ///
    /// Fails with ``KeychainError/itemNotFound`` if no item exists for the key.
    /// Use ``upsert(_:for:)`` to create or update in a single call.
    ///
    /// - Parameters:
    ///   - value: The new value to store.
    ///   - key: The ``KeychainKey`` that identifies the item.
    /// - Throws: ``KeychainError/itemNotFound`` if no item exists,
    ///   or another ``KeychainError`` if the operation fails.
    ///
    /// ```swift
    /// try await Keychain.shared.update("new-token", for: key)
    /// ```
    public func update<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        logKeychainOperationStarted("update", service: key.service, account: key.account)
        do {
            try backend.update(
                matching: identityQuery(for: key),
                to: KeychainAttributes(
                    data: try value.keychainData(),
                    label: key.label,
                    comment: key.comment,
                    accessibility: key.accessibility
                )
            )
            notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .updated)
            logKeychainOperationSucceeded("update", service: key.service, account: key.account)
        } catch {
            logKeychainOperationFailed("update", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    /// Saves a value to the keychain, updating the existing item if one already exists.
    ///
    /// This is the recommended write method when the item may or may not be present.
    ///
    /// - Parameters:
    ///   - value: The value to persist.
    ///   - key: The ``KeychainKey`` that identifies the item.
    /// - Throws: ``KeychainError`` if the underlying save or update operation fails.
    ///
    /// ```swift
    /// try await Keychain.shared.upsert("refreshed-token", for: key)
    /// ```
    public func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        logKeychainOperationStarted("upsert", service: key.service, account: key.account)
        do {
            try save(value, for: key)
        } catch KeychainError.duplicateItem {
            SwiftyChainLoggers.keychain.debug(
                "upsert found duplicate item; updating instead for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            try update(value, for: key)
            logKeychainOperationSucceeded("upsert", service: key.service, account: key.account)
        } catch {
            logKeychainOperationFailed("upsert", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    /// Deletes a keychain item.
    ///
    /// This is a no-op when no item exists for the key.
    ///
    /// - Parameter key: The ``KeychainKey`` that identifies the item to delete.
    /// - Throws: ``KeychainError`` if the underlying operation fails.
    ///
    /// ```swift
    /// try await Keychain.shared.delete(key: key)
    /// ```
    public func delete<T: KeychainStorable>(key: KeychainKey<T>) throws {
        logKeychainOperationStarted("delete", service: key.service, account: key.account)
        do {
            try backend.delete(matching: identityQuery(for: key))
            notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .deleted)
            logKeychainOperationSucceeded("delete", service: key.service, account: key.account)
        } catch {
            logKeychainOperationFailed("delete", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    /// Deletes all generic-password items for a service, including iCloud-synchronized ones.
    ///
    /// - Parameters:
    ///   - service: The service name whose items should be deleted.
    ///   - accessGroup: The access group to target. Pass `nil` for the default group.
    /// - Throws: ``KeychainError`` if the underlying operation fails.
    ///
    /// ```swift
    /// try await Keychain.shared.deleteAll(service: "com.example.app")
    /// ```
    public func deleteAll(service: String, accessGroup: String? = nil) throws {
        try deleteAllItems(matching: .allItems(service: service, accessGroup: accessGroup))
    }

    /// Deletes only iCloud-synchronized generic-password items for a service.
    ///
    /// Items that are not synchronizable are left untouched.
    ///
    /// - Parameters:
    ///   - service: The service name whose synchronizable items should be deleted.
    ///   - accessGroup: The access group to target. Pass `nil` for the default group.
    /// - Throws: ``KeychainError`` if the underlying operation fails.
    ///
    /// ```swift
    /// try await Keychain.shared.deleteAllSynchronizable(service: "com.example.app")
    /// ```
    public func deleteAllSynchronizable(service: String, accessGroup: String? = nil) throws {
        try deleteAllItems(matching: .synchronizableItems(service: service, accessGroup: accessGroup))
    }

    /// Deletes all keychain items matching a custom ``KeychainDeleteQuery``.
    ///
    /// Use this method when you need fine-grained control over which items are removed,
    /// such as targeting a specific item class or access group.
    ///
    /// - Parameter query: A ``KeychainDeleteQuery`` describing the items to delete.
    /// - Throws: ``KeychainError`` if the underlying operation fails.
    ///
    /// ```swift
    /// let query = KeychainDeleteQuery(service: "com.example.app", onlySynchronizable: true)
    /// try await Keychain.shared.deleteAllItems(matching: query)
    /// ```
    public func deleteAllItems(matching query: KeychainDeleteQuery) throws {
        let isSynchronizable: Bool? =
            if query.onlySynchronizable {
                true
            } else if query.includeSynchronizable {
                nil
            } else {
                false
            }
        logBulkDeleteStarted(query: query)
        do {
            // Internet passwords use kSecAttrServer, not kSecAttrService.
            let keychainQuery =
                query.itemClass == .internetPassword
                ? KeychainQuery(
                    itemClass: query.itemClass,
                    accessGroup: query.accessGroup,
                    isSynchronizable: isSynchronizable,
                    server: query.service
                )
                : KeychainQuery(
                    itemClass: query.itemClass,
                    service: query.service,
                    accessGroup: query.accessGroup,
                    isSynchronizable: isSynchronizable
                )
            try backend.delete(matching: keychainQuery)
            if let service = query.service {
                notify(service: service, account: nil, accessGroup: query.accessGroup, kind: .bulkDeleted)
            }
            logBulkDeleteSucceeded(query: query)
        } catch {
            logBulkDeleteFailed(query: query, error: error)
            throw error
        }
    }

    /// Returns whether a keychain item exists for the given key.
    ///
    /// - Parameter key: The ``KeychainKey`` that identifies the item.
    /// - Returns: `true` if an item exists; `false` otherwise.
    /// - Throws: ``KeychainError`` for failures other than item not found.
    ///
    /// ```swift
    /// if try await Keychain.shared.exists(key: key) {
    ///     // item is already stored
    /// }
    /// ```
    public func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool {
        do {
            _ = try backend.copyMatching(identityQuery(for: key))
            return true
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "exists returned false for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            return false
        } catch {
            logKeychainOperationFailed("exists", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    /// Returns all account identifiers stored under a given service.
    ///
    /// Useful for listing all keychain items owned by a service without loading their values.
    ///
    /// - Parameters:
    ///   - service: The service name whose accounts to enumerate.
    ///   - accessGroup: The access group to query. Pass `nil` for the default group.
    /// - Returns: An array of account strings, or an empty array when no items are found.
    /// - Throws: ``KeychainError`` if the query fails for a reason other than no items found.
    ///
    /// ```swift
    /// let accounts = try await Keychain.shared.allAccounts(service: "com.example.app")
    /// import OSLog
    ///
    /// let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")
    /// for account in accounts {
    ///     logger.debug("Found account: \(account, privacy: .private(mask: .hash))")
    /// }
    /// ```
    public func allAccounts(service: String, accessGroup: String? = nil) throws -> [String] {
        let result: KeychainQueryResult
        do {
            result = try backend.copyMatching(
                KeychainQuery(
                    itemClass: .genericPassword,
                    service: service,
                    accessGroup: accessGroup,
                    returnAttributes: true,
                    matchLimit: .all
                )
            )
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "allAccounts returned no items for service=\(service, privacy: .private(mask: .hash))"
            )
            return []
        }
        guard case .items(let items) = result else {
            SwiftyChainLoggers.keychain.error(
                "allAccounts returned unexpected result for service=\(service, privacy: .private(mask: .hash))"
            )
            throw KeychainError.unexpectedData
        }
        return items.compactMap { item in
            guard case .attributes(let attributes) = item else { return nil }
            return attributes.compactMap { attribute in
                if case .account(let account) = attribute { return account }
                return nil
            }.first
        }
    }

    /// Saves an internet password to the keychain.
    ///
    /// - Parameters:
    ///   - password: The password string to store.
    ///   - key: The ``InternetPasswordKey`` describing the server and account.
    /// - Throws: ``KeychainError/duplicateItem`` if a password already exists for the key,
    ///   or another ``KeychainError`` if the operation fails.
    ///
    /// ```swift
    /// let key = InternetPasswordKey(server: "api.example.com", account: "user@example.com")
    /// try await Keychain.shared.saveInternetPassword("s3cr3t", for: key)
    /// ```
    public func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws {
        logKeychainOperationStarted("saveInternetPassword", service: key.server, account: key.account)
        do {
            try backend.add(internetAddQuery(for: key), data: password.keychainData())
            notify(service: key.server, account: key.account, accessGroup: key.accessGroup, kind: .saved)
            logKeychainOperationSucceeded("saveInternetPassword", service: key.server, account: key.account)
        } catch {
            logKeychainOperationFailed("saveInternetPassword", service: key.server, account: key.account, error: error)
            throw error
        }
    }

    /// Loads an internet password from the keychain.
    ///
    /// - Parameter key: The ``InternetPasswordKey`` describing the server and account.
    /// - Returns: The stored password string.
    /// - Throws: ``KeychainError/itemNotFound`` if no password is stored for the key,
    ///   or another ``KeychainError`` on failure.
    ///
    /// ```swift
    /// let password = try await Keychain.shared.loadInternetPassword(for: key)
    /// ```
    public func loadInternetPassword(for key: InternetPasswordKey) throws -> String {
        logKeychainOperationStarted("loadInternetPassword", service: key.server, account: key.account)
        do {
            let result = try backend.copyMatching(internetIdentityQuery(for: key, returnData: true))
            guard case .data(let data) = result else {
                SwiftyChainLoggers.keychain.error(
                    "loadInternetPassword returned unexpected result for server=\(key.server, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
                )
                throw KeychainError.unexpectedData
            }
            return try String.fromKeychainData(data)
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "loadInternetPassword returned item not found for server=\(key.server, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            throw KeychainError.itemNotFound
        } catch {
            logKeychainOperationFailed("loadInternetPassword", service: key.server, account: key.account, error: error)
            throw error
        }
    }

    /// Deletes an internet password from the keychain.
    ///
    /// This is a no-op when no password is stored for the key.
    ///
    /// - Parameter key: The ``InternetPasswordKey`` describing the item to delete.
    /// - Throws: ``KeychainError`` if the underlying operation fails.
    ///
    /// ```swift
    /// try await Keychain.shared.deleteInternetPassword(for: key)
    /// ```
    public func deleteInternetPassword(for key: InternetPasswordKey) throws {
        logKeychainOperationStarted("deleteInternetPassword", service: key.server, account: key.account)
        do {
            try backend.delete(matching: internetIdentityQuery(for: key))
            notify(service: key.server, account: key.account, accessGroup: key.accessGroup, kind: .deleted)
            logKeychainOperationSucceeded("deleteInternetPassword", service: key.server, account: key.account)
        } catch {
            logKeychainOperationFailed(
                "deleteInternetPassword",
                service: key.server,
                account: key.account,
                error: error
            )
            throw error
        }
    }

    #if Observation
        /// Returns an async stream that emits an event whenever a keychain item changes for the given service.
        ///
        /// The stream delivers a ``KeychainChangeEvent`` after each save, update, delete, or
        /// bulk-delete performed through this actor for the specified service.
        /// The stream terminates when the caller's task is cancelled.
        ///
        /// > Note: Changes made through ``KeychainStorage`` or a different ``Keychain`` actor
        /// > instance are not reflected in this stream.
        ///
        /// - Parameters:
        ///   - service: The service name to observe.
        ///   - accessGroup: The access group to filter on. Pass `nil` to observe all groups.
        /// - Returns: An `AsyncStream` of ``KeychainChangeEvent`` values.
        ///
        /// ```swift
        /// import OSLog
        ///
        /// let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")
        ///
        /// for await event in await Keychain.shared.observeKeychainChanges(service: "com.example.app") {
        ///     switch event.kind {
        ///     case .saved:       logger.debug("Saved keychain item")
        ///     case .updated:     logger.debug("Updated keychain item")
        ///     case .deleted:     logger.debug("Deleted keychain item")
        ///     case .bulkDeleted: logger.debug("Deleted all keychain items")
        ///     }
        /// }
        /// ```
        public func observeKeychainChanges(
            service: String,
            accessGroup: String? = nil
        ) -> AsyncStream<KeychainChangeEvent> {
            let id = UUID()
            return AsyncStream { continuation in
                SwiftyChainLoggers.observation.debug(
                    "Registered observer for service=\(service, privacy: .private(mask: .hash))"
                )
                observers[id] = Observer(service: service, accessGroup: accessGroup, continuation: continuation)
                continuation.onTermination = { [weak self] _ in
                    Task { await self?.removeObserver(id: id) }
                }
            }
        }

        private struct Observer: Sendable {
            let service: String
            let accessGroup: String?
            let continuation: AsyncStream<KeychainChangeEvent>.Continuation
        }

        private func removeObserver(id: UUID) {
            SwiftyChainLoggers.observation.debug("Removed observer")
            observers.removeValue(forKey: id)
        }

        private func notify(service: String, account: String?, accessGroup: String?, kind: MutationKind) {
            let eventKind: KeychainChangeEvent.Kind =
                switch kind {
                case .saved: .saved
                case .updated: .updated
                case .deleted: .deleted
                case .bulkDeleted: .bulkDeleted
                }
            let event = KeychainChangeEvent(service: service, account: account, kind: eventKind)
            SwiftyChainLoggers.observation.debug(
                "Emitting observation event=\(String(describing: eventKind), privacy: .public) service=\(service, privacy: .private(mask: .hash)) account=\(account ?? "<all>", privacy: .private(mask: .hash))"
            )
            for observer in observers.values
            where observer.service == service
                && (observer.accessGroup == nil || observer.accessGroup == accessGroup)
            {
                observer.continuation.yield(event)
            }
        }
    #else
        private func notify(service: String, account: String?, accessGroup: String?, kind: MutationKind) {}
    #endif

    // Identity-only query: includes the attributes Apple's Security framework
    // uses to match an existing item (class + service + account + accessGroup +
    // synchronizable). Used for load/update/delete/exists so non-identity
    // attributes like label, comment, or accessibility don't break the match.
    private func identityQuery<T: KeychainStorable>(
        for key: KeychainKey<T>,
        returnData: Bool = false,
        returnAttributes: Bool = false
    ) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable,
            returnData: returnData,
            returnAttributes: returnAttributes
        )
    }

    // Full query for SecItemAdd: writes accessibility, label, and comment as
    // attributes alongside the identity fields.
    private func addQuery<T: KeychainStorable>(for key: KeychainKey<T>) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            accessibility: key.accessibility,
            isSynchronizable: key.isSynchronizable,
            label: key.label,
            comment: key.comment
        )
    }

    private func internetIdentityQuery(
        for key: InternetPasswordKey,
        returnData: Bool = false
    ) -> KeychainQuery {
        KeychainQuery(
            itemClass: .internetPassword,
            account: key.account,
            accessGroup: key.accessGroup,
            returnData: returnData,
            server: key.server,
            port: key.port,
            path: key.path,
            internetProtocol: key.protocol,
            authenticationType: key.authenticationType
        )
    }

    private func internetAddQuery(for key: InternetPasswordKey) -> KeychainQuery {
        KeychainQuery(
            itemClass: .internetPassword,
            account: key.account,
            accessGroup: key.accessGroup,
            accessibility: key.accessibility,
            server: key.server,
            port: key.port,
            path: key.path,
            internetProtocol: key.protocol,
            authenticationType: key.authenticationType
        )
    }

    private func logKeychainOperationStarted(_ operation: StaticString, service: String, account: String?) {
        SwiftyChainLoggers.keychain.debug(
            "\(operation) started for service=\(service, privacy: .private(mask: .hash)) account=\(account ?? "<none>", privacy: .private(mask: .hash))"
        )
    }

    private func logKeychainOperationSucceeded(_ operation: StaticString, service: String, account: String?) {
        SwiftyChainLoggers.keychain.debug(
            "\(operation) succeeded for service=\(service, privacy: .private(mask: .hash)) account=\(account ?? "<none>", privacy: .private(mask: .hash))"
        )
    }

    private func logKeychainOperationFailed(
        _ operation: StaticString,
        service: String,
        account: String?,
        error: any Error
    ) {
        let errorName = keychainLogErrorName(for: error)
        SwiftyChainLoggers.keychain.error(
            "\(operation) failed for service=\(service, privacy: .private(mask: .hash)) account=\(account ?? "<none>", privacy: .private(mask: .hash)) error=\(errorName, privacy: .public)"
        )
    }

    private func logBulkDeleteStarted(query: KeychainDeleteQuery) {
        SwiftyChainLoggers.keychain.debug(
            "deleteAllItems started for service=\(query.service ?? "<all>", privacy: .private(mask: .hash)) accessGroup=\(query.accessGroup ?? "<none>", privacy: .private(mask: .hash)) includeSynchronizable=\(query.includeSynchronizable, privacy: .public) onlySynchronizable=\(query.onlySynchronizable, privacy: .public)"
        )
    }

    private func logBulkDeleteSucceeded(query: KeychainDeleteQuery) {
        SwiftyChainLoggers.keychain.debug(
            "deleteAllItems succeeded for service=\(query.service ?? "<all>", privacy: .private(mask: .hash)) accessGroup=\(query.accessGroup ?? "<none>", privacy: .private(mask: .hash))"
        )
    }

    private func logBulkDeleteFailed(query: KeychainDeleteQuery, error: any Error) {
        let errorName = keychainLogErrorName(for: error)
        SwiftyChainLoggers.keychain.error(
            "deleteAllItems failed for service=\(query.service ?? "<all>", privacy: .private(mask: .hash)) accessGroup=\(query.accessGroup ?? "<none>", privacy: .private(mask: .hash)) error=\(errorName, privacy: .public)"
        )
    }

    private func keychainLogErrorName(for error: any Error) -> String {
        if let keychainError = error as? KeychainError {
            return keychainError.logName
        }
        return String(reflecting: type(of: error))
    }
}
