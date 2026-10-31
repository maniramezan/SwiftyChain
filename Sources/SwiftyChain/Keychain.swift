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
/// import OSLog
///
/// let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")
///
/// for await event in await Keychain.shared.observeKeychainChanges(service: "com.example.app") {
///     logger.debug("Observed change: \(String(describing: event.kind), privacy: .public)")
/// }
/// ```
public actor Keychain: KeychainProtocol {
    /// The shared keychain instance backed by the platform keychain.
    ///
    /// On Apple platforms this is the system Keychain. On Linux it is the
    /// freedesktop Secret Service (GNOME Keyring or KWallet) via libsecret.
    public static let shared = Keychain()

    package let engine: KeychainEngine

    package var backend: any SecureStorageBackend { engine.backend }

    /// Creates a new ``Keychain`` instance backed by the platform keychain.
    public init() {
        self.init(backend: PlatformDefaultBackend.make())
    }

    package init(backend: any SecureStorageBackend) {
        self.engine = KeychainEngine(backend: backend)
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
        try engine.save(value, for: key)
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
        try engine.load(key: key)
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
        try engine.loadIfPresent(key: key)
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
        try engine.update(value, for: key)
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
        try engine.upsert(value, for: key)
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
        try engine.delete(key: key)
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
        try engine.deleteAllItems(matching: query)
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
        try engine.exists(key: key)
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
        try engine.allAccounts(service: service, accessGroup: accessGroup)
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
        try engine.saveInternetPassword(password, for: key)
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
        try engine.loadInternetPassword(for: key)
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
        try engine.deleteInternetPassword(for: key)
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
            engine.observeKeychainChanges(service: service, accessGroup: accessGroup)
        }
    #endif
}

#if Observation
    extension Keychain: KeychainObserving {}
#endif

#if Cryptography && canImport(Security)
    extension Keychain: KeychainCryptoStoring {}
#endif
