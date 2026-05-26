/// Public protocol for depending on keychain behavior in application code.
///
/// ``Keychain`` conforms to this protocol.
///
/// Declare your feature code against `KeychainProtocol` so tests can inject an
/// in-memory implementation without touching the real system keychain. The
/// `SwiftyChainTesting` product provides `InMemoryKeychain` for exactly this purpose.
///
/// ```swift
/// // Feature code
/// func bootstrap(keychain: some KeychainProtocol) async throws {
///     let key = KeychainKey<String>(service: "com.example", account: "token")
///     if let token = try await keychain.loadIfPresent(key: key) {
///         configure(token: token)
///     }
/// }
///
/// // Tests
/// let keychain = InMemoryKeychain()
/// try await bootstrap(keychain: keychain)
/// ```
public protocol KeychainProtocol: Actor, Sendable {
    /// Saves a new keychain item.
    ///
    /// - Throws: ``KeychainError/duplicateItem`` if an item with the same identity already exists.
    ///   Prefer ``upsert(_:for:)`` when you want create-or-replace semantics.
    func save<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws

    /// Loads an existing keychain item.
    ///
    /// - Throws: ``KeychainError/itemNotFound`` if no item matches `key`.
    ///   Use ``loadIfPresent(key:)`` to get an optional instead.
    func load<T: KeychainStorable>(key: KeychainKey<T>) throws -> T

    /// Loads a keychain item, returning `nil` if it does not exist.
    ///
    /// Equivalent to calling ``load(key:)`` and catching ``KeychainError/itemNotFound``.
    func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T?

    /// Replaces the value of an existing keychain item.
    ///
    /// - Throws: ``KeychainError/itemNotFound`` if no item matching `key` exists.
    ///   Prefer ``upsert(_:for:)`` when you want create-or-replace semantics.
    func update<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws

    /// Saves or replaces a keychain item in a single call.
    ///
    /// This is the recommended write method for most cases. It creates the item if
    /// it does not exist, or updates it if it does, with no error on either path.
    func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws

    /// Removes a keychain item.
    ///
    /// This is a no-op if the item does not exist.
    func delete<T: KeychainStorable>(key: KeychainKey<T>) throws

    /// Removes all generic-password items stored under `service`.
    ///
    /// Pass `accessGroup` to restrict deletion to items in a specific keychain access group.
    func deleteAll(service: String, accessGroup: String?) throws

    /// Removes all iCloud-synchronizable generic-password items stored under `service`.
    func deleteAllSynchronizable(service: String, accessGroup: String?) throws

    /// Removes all items matching a structured query.
    ///
    /// Use ``KeychainDeleteQuery`` to build targeted bulk-delete operations across item
    /// classes, access groups, or synchronizability attributes.
    func deleteAllItems(matching query: KeychainDeleteQuery) throws

    /// Returns `true` if a keychain item exists for `key`, without loading its value.
    func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool

    /// Returns all account names stored under `service`.
    ///
    /// Pass `accessGroup` to restrict results to a specific keychain access group.
    func allAccounts(service: String, accessGroup: String?) throws -> [String]

    /// Saves an internet password.
    ///
    /// - Throws: ``KeychainError/duplicateItem`` if an item with the same identity already exists.
    func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws

    /// Loads an internet password.
    ///
    /// - Throws: ``KeychainError/itemNotFound`` if no matching item exists.
    func loadInternetPassword(for key: InternetPasswordKey) throws -> String

    /// Removes an internet password.
    func deleteInternetPassword(for key: InternetPasswordKey) throws

    #if Observation
        /// Returns an `AsyncStream` that emits a ``KeychainChangeEvent`` each time an item
        /// in `service` is saved, updated, deleted, or bulk-deleted.
        ///
        /// The stream runs until the caller drops the reference or cancels the enclosing task.
        /// Multiple concurrent observers on the same service are each notified independently.
        ///
        /// > Note: Changes made through ``KeychainStorage`` bypass the ``Keychain`` actor
        /// > and do **not** appear in this stream. Write through ``Keychain`` directly if
        /// > change notifications are required.
        func observeKeychainChanges(
            service: String,
            accessGroup: String?
        ) -> AsyncStream<KeychainChangeEvent>
    #endif
    #if Cryptography
        /// Saves a cryptographic key to the keychain.
        ///
        /// - Throws: ``KeychainError/duplicateItem`` if a key with the same reference already exists.
        func saveCryptoKey(_ key: StoredSecKey, for keyRef: CryptoKeyReference<StoredSecKey>) throws

        /// Loads a cryptographic key from the keychain.
        ///
        /// - Throws: ``KeychainError/itemNotFound`` if no key matching `keyRef` exists.
        func loadCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws -> StoredSecKey

        /// Removes a cryptographic key from the keychain.
        func deleteCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws
    #endif
}

extension KeychainProtocol {
    public func deleteAll(service: String) throws {
        try deleteAll(service: service, accessGroup: nil)
    }

    public func deleteAllSynchronizable(service: String) throws {
        try deleteAllSynchronizable(service: service, accessGroup: nil)
    }

    public func allAccounts(service: String) throws -> [String] {
        try allAccounts(service: service, accessGroup: nil)
    }

    #if Observation
        public func observeKeychainChanges(service: String) -> AsyncStream<KeychainChangeEvent> {
            observeKeychainChanges(service: service, accessGroup: nil)
        }
    #endif
}
