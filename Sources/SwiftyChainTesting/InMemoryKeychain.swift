import Foundation
import SwiftyChain

/// An in-memory implementation of `KeychainProtocol` for use in tests.
///
/// `InMemoryKeychain` stores items in memory instead of the system keychain,
/// so tests run fast, stay isolated, and do not require keychain entitlements.
/// It runs the same engine as `Keychain`, so lookups, duplicate detection,
/// and bulk deletes follow the real keychain's rules.
///
/// ## Basic usage
///
/// Declare your feature code against `KeychainProtocol`, then inject
/// `InMemoryKeychain` in tests:
///
/// ```swift
/// import SwiftyChain
/// import SwiftyChainTesting
///
/// let keychain: any KeychainProtocol = InMemoryKeychain()
/// let key = KeychainKey<String>(service: "com.example", account: "token")
///
/// try await keychain.upsert("secret", for: key)
/// let value = try await keychain.load(key: key) // "secret"
/// ```
///
/// Each instance starts empty. Create a fresh one per test to guarantee isolation.
///
/// ## Thread safety
///
/// `InMemoryKeychain` is an `actor`, matching the concurrency contract of
/// `KeychainProtocol`. All mutations are serialized automatically.
///
/// ## Conditional APIs
///
/// When the `observation` trait is enabled, `InMemoryKeychain` fully implements
/// `observeKeychainChanges(service:accessGroup:)`. Events are
/// emitted synchronously during mutations, making async observation easy to assert on.
///
/// When the `cryptography` trait is enabled, `InMemoryKeychain` implements
/// `saveCryptoKey(_:for:)`, `loadCryptoKey(keyRef:)`, and `deleteCryptoKey(keyRef:)`.
public actor InMemoryKeychain: KeychainProtocol {
    private let engine = KeychainEngine(backend: InMemoryStorageBackend())

    /// Creates a new, empty in-memory keychain.
    public init() {}

    /// Saves a new item.
    ///
    /// - Throws: `KeychainError.duplicateItem` if an item with the same identity already exists.
    public func save<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        try engine.save(value, for: key)
    }

    /// Loads an existing item.
    ///
    /// - Throws: `KeychainError.itemNotFound` if no item matches `key`.
    public func load<T: KeychainStorable>(key: KeychainKey<T>) throws -> T {
        try engine.load(key: key)
    }

    /// Loads an item, returning `nil` if it does not exist.
    public func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T? {
        try engine.loadIfPresent(key: key)
    }

    /// Replaces an existing item.
    ///
    /// - Throws: `KeychainError.itemNotFound` if no item matching `key` exists.
    public func update<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        try engine.update(value, for: key)
    }

    /// Saves or replaces an item in a single call.
    ///
    /// This is the recommended write method for most tests — it creates the item if
    /// absent, or updates it if already present.
    public func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        try engine.upsert(value, for: key)
    }

    /// Removes an item. This is a no-op if the item does not exist.
    public func delete<T: KeychainStorable>(key: KeychainKey<T>) throws {
        try engine.delete(key: key)
    }

    /// Removes all generic-password items stored under `service`.
    public func deleteAll(service: String, accessGroup: String? = nil) throws {
        try deleteAllItems(matching: .allItems(service: service, accessGroup: accessGroup))
    }

    /// Removes all iCloud-synchronizable items stored under `service`.
    public func deleteAllSynchronizable(service: String, accessGroup: String? = nil) throws {
        try deleteAllItems(matching: .synchronizableItems(service: service, accessGroup: accessGroup))
    }

    /// Removes all items matching a structured query.
    public func deleteAllItems(matching query: KeychainDeleteQuery) throws {
        try engine.deleteAllItems(matching: query)
    }

    /// Returns `true` if an item exists for `key`, without loading its value.
    public func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool {
        try engine.exists(key: key)
    }

    /// Returns all account names stored under `service`.
    public func allAccounts(service: String, accessGroup: String? = nil) throws -> [String] {
        try engine.allAccounts(service: service, accessGroup: accessGroup)
    }

    /// Saves an internet password.
    ///
    /// - Throws: `KeychainError.duplicateItem` if an item with the same identity already exists.
    public func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws {
        try engine.saveInternetPassword(password, for: key)
    }

    /// Loads an internet password.
    ///
    /// - Throws: `KeychainError.itemNotFound` if no matching item exists.
    public func loadInternetPassword(for key: InternetPasswordKey) throws -> String {
        try engine.loadInternetPassword(for: key)
    }

    /// Removes an internet password.
    public func deleteInternetPassword(for key: InternetPasswordKey) throws {
        try engine.deleteInternetPassword(for: key)
    }

    #if Observation
        /// Returns an `AsyncStream` that emits a `KeychainChangeEvent` each time an item
        /// in `service` is saved, updated, deleted, or bulk-deleted.
        ///
        /// Events are emitted synchronously during each mutation, making it
        /// straightforward to observe and assert on changes in async tests.
        public func observeKeychainChanges(
            service: String,
            accessGroup: String? = nil
        ) -> AsyncStream<KeychainChangeEvent> {
            engine.observeKeychainChanges(service: service, accessGroup: accessGroup)
        }
    #endif

    #if Cryptography && canImport(Security)
        /// Saves a cryptographic key.
        ///
        /// Replaces any previously saved key for the same `keyRef`.
        public func saveCryptoKey(_ key: StoredSecKey, for keyRef: CryptoKeyReference<StoredSecKey>) throws {
            try engine.saveCryptoKey(key, for: keyRef)
        }

        /// Loads a cryptographic key.
        ///
        /// - Throws: `KeychainError.itemNotFound` if no key matching `keyRef` was saved.
        public func loadCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws -> StoredSecKey {
            try engine.loadCryptoKey(keyRef: keyRef)
        }

        /// Removes a cryptographic key.
        public func deleteCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws {
            try engine.deleteCryptoKey(keyRef: keyRef)
        }
    #endif
}

#if Observation
    extension InMemoryKeychain: KeychainObserving {}
#endif

#if Cryptography && canImport(Security)
    extension InMemoryKeychain: KeychainCryptoStoring {}
#endif
