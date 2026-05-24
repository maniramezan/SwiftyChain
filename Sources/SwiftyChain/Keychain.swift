import Foundation

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
/// for await event in await Keychain.shared.observeKeychainChanges(service: "com.example.app") {
///     print(event.kind, event.account ?? "(all)")
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
        try backend.add(addQuery(for: key), data: value.keychainData())
        notify(service: key.service, account: key.account, kind: .saved)
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
        let result = try backend.copyMatching(identityQuery(for: key, returnData: true))
        guard case .data(let data) = result else {
            throw KeychainError.unexpectedData
        }
        return try T.fromKeychainData(data)
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
        try backend.update(
            matching: identityQuery(for: key),
            to: KeychainAttributes(
                data: try value.keychainData(),
                label: key.label,
                comment: key.comment,
                accessibility: key.accessibility
            )
        )
        notify(service: key.service, account: key.account, kind: .updated)
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
        do {
            try save(value, for: key)
        } catch KeychainError.duplicateItem {
            try update(value, for: key)
        }
    }

    /// Deletes a keychain item.
    ///
    /// - Parameter key: The ``KeychainKey`` that identifies the item to delete.
    /// - Throws: ``KeychainError/itemNotFound`` if no item exists for the key,
    ///   or another ``KeychainError`` if the operation fails.
    ///
    /// ```swift
    /// try await Keychain.shared.delete(key: key)
    /// ```
    public func delete<T: KeychainStorable>(key: KeychainKey<T>) throws {
        try backend.delete(matching: identityQuery(for: key))
        notify(service: key.service, account: key.account, kind: .deleted)
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
        try backend.delete(
            matching: KeychainQuery(
                itemClass: query.itemClass,
                service: query.service,
                accessGroup: query.accessGroup,
                isSynchronizable: isSynchronizable
            )
        )
        if let service = query.service {
            notify(service: service, account: nil, kind: .bulkDeleted)
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
            return false
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
    /// for account in accounts { print("Found account:", account) }
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
            return []
        }
        guard case .items(let items) = result else {
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
        try backend.add(internetAddQuery(for: key), data: password.keychainData())
        notify(service: key.server, account: key.account, kind: .saved)
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
        let result = try backend.copyMatching(internetIdentityQuery(for: key, returnData: true))
        guard case .data(let data) = result else {
            throw KeychainError.unexpectedData
        }
        return try String.fromKeychainData(data)
    }

    /// Deletes an internet password from the keychain.
    ///
    /// - Parameter key: The ``InternetPasswordKey`` describing the item to delete.
    /// - Throws: ``KeychainError/itemNotFound`` if no password is stored for the key,
    ///   or another ``KeychainError`` on failure.
    ///
    /// ```swift
    /// try await Keychain.shared.deleteInternetPassword(for: key)
    /// ```
    public func deleteInternetPassword(for key: InternetPasswordKey) throws {
        try backend.delete(matching: internetIdentityQuery(for: key))
        notify(service: key.server, account: key.account, kind: .deleted)
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
        /// for await event in await Keychain.shared.observeKeychainChanges(service: "com.example.app") {
        ///     switch event.kind {
        ///     case .saved:       print("Saved:", event.account ?? "")
        ///     case .updated:     print("Updated:", event.account ?? "")
        ///     case .deleted:     print("Deleted:", event.account ?? "")
        ///     case .bulkDeleted: print("All items deleted")
        ///     }
        /// }
        /// ```
        public func observeKeychainChanges(
            service: String,
            accessGroup: String? = nil
        ) -> AsyncStream<KeychainChangeEvent> {
            let id = UUID()
            return AsyncStream { continuation in
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
            observers.removeValue(forKey: id)
        }

        private func notify(service: String, account: String?, kind: MutationKind) {
            let eventKind: KeychainChangeEvent.Kind =
                switch kind {
                case .saved: .saved
                case .updated: .updated
                case .deleted: .deleted
                case .bulkDeleted: .bulkDeleted
                }
            let event = KeychainChangeEvent(service: service, account: account, kind: eventKind)
            for observer in observers.values where observer.service == service {
                observer.continuation.yield(event)
            }
        }
    #else
        private func notify(service: String, account: String?, kind: MutationKind) {}
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
}
