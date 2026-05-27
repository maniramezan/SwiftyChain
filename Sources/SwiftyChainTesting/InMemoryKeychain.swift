import Foundation
import SwiftyChain

/// An in-memory implementation of `KeychainProtocol` for use in tests.
///
/// `InMemoryKeychain` stores items in dictionaries instead of the system keychain,
/// so tests run fast, stay isolated, and do not require keychain entitlements.
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
    private struct GenericPasswordIdentity: Hashable {
        let service: String
        let account: String
        let accessGroup: String?
        let isSynchronizable: Bool
    }

    private struct InternetPasswordIdentity: Hashable {
        let server: String
        let account: String
        let port: Int?
        let path: String?
        let internetProtocol: InternetProtocol
        let authenticationType: AuthenticationType
        let accessGroup: String?
    }

    private struct GenericPasswordRecord: Sendable {
        let data: Data
        let accessibility: KeychainAccessibility
        let label: String?
        let comment: String?
    }

    private struct InternetPasswordRecord: Sendable {
        let password: String
        let accessibility: KeychainAccessibility
    }

    private var genericPasswords: [GenericPasswordIdentity: GenericPasswordRecord] = [:]
    private var internetPasswords: [InternetPasswordIdentity: InternetPasswordRecord] = [:]
    #if Observation
        private var observers: [UUID: Observer] = [:]
    #endif

    /// Creates a new, empty in-memory keychain.
    public init() {}

    /// Saves a new item.
    ///
    /// - Throws: `KeychainError.duplicateItem` if an item with the same identity already exists.
    public func save<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        let identity = GenericPasswordIdentity(
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable
        )
        if genericPasswords[identity] != nil {
            throw KeychainError.duplicateItem
        }
        genericPasswords[identity] = GenericPasswordRecord(
            data: try value.keychainData(),
            accessibility: key.accessibility,
            label: key.label,
            comment: key.comment
        )
        notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .saved)
    }

    /// Loads an existing item.
    ///
    /// - Throws: `KeychainError.itemNotFound` if no item matches `key`.
    public func load<T: KeychainStorable>(key: KeychainKey<T>) throws -> T {
        let identity = GenericPasswordIdentity(
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable
        )
        guard let record = genericPasswords[identity] else {
            throw KeychainError.itemNotFound
        }
        return try T.fromKeychainData(record.data)
    }

    /// Loads an item, returning `nil` if it does not exist.
    public func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T? {
        do {
            return try load(key: key)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

    /// Replaces an existing item.
    ///
    /// - Throws: `KeychainError.itemNotFound` if no item matching `key` exists.
    public func update<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        let identity = GenericPasswordIdentity(
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable
        )
        guard genericPasswords[identity] != nil else {
            throw KeychainError.itemNotFound
        }
        genericPasswords[identity] = GenericPasswordRecord(
            data: try value.keychainData(),
            accessibility: key.accessibility,
            label: key.label,
            comment: key.comment
        )
        notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .updated)
    }

    /// Saves or replaces an item in a single call.
    ///
    /// This is the recommended write method for most tests — it creates the item if
    /// absent, or updates it if already present.
    public func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        do {
            try save(value, for: key)
        } catch KeychainError.duplicateItem {
            try update(value, for: key)
        }
    }

    /// Removes an item. This is a no-op if the item does not exist.
    public func delete<T: KeychainStorable>(key: KeychainKey<T>) throws {
        let identity = GenericPasswordIdentity(
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable
        )
        genericPasswords.removeValue(forKey: identity)
        notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .deleted)
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
        switch query.itemClass {
        case .genericPassword:
            genericPasswords = genericPasswords.filter { key, _ in
                !matchesGenericPassword(key, query: query)
            }
        case .internetPassword:
            internetPasswords = internetPasswords.filter { key, _ in
                !matchesInternetPassword(key, query: query)
            }
        #if Cryptography
            case .cryptographicKey:
                break
        #endif
        }
        if let service = query.service {
            notify(service: service, account: nil, accessGroup: query.accessGroup, kind: .bulkDeleted)
        }
    }

    /// Returns `true` if an item exists for `key`, without loading its value.
    public func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool {
        let identity = GenericPasswordIdentity(
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable
        )
        return genericPasswords[identity] != nil
    }

    /// Returns all account names stored under `service`.
    public func allAccounts(service: String, accessGroup: String? = nil) throws -> [String] {
        genericPasswords.keys.compactMap { key in
            guard key.service == service else { return nil }
            guard accessGroup == nil || key.accessGroup == accessGroup else { return nil }
            return key.account
        }
    }

    /// Saves an internet password.
    ///
    /// - Throws: `KeychainError.duplicateItem` if an item with the same identity already exists.
    public func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws {
        let identity = InternetPasswordIdentity(
            server: key.server,
            account: key.account,
            port: key.port,
            path: key.path,
            internetProtocol: key.protocol,
            authenticationType: key.authenticationType,
            accessGroup: key.accessGroup
        )
        if internetPasswords[identity] != nil {
            throw KeychainError.duplicateItem
        }
        internetPasswords[identity] = InternetPasswordRecord(
            password: password,
            accessibility: key.accessibility
        )
        notify(service: key.server, account: key.account, accessGroup: key.accessGroup, kind: .saved)
    }

    /// Loads an internet password.
    ///
    /// - Throws: `KeychainError.itemNotFound` if no matching item exists.
    public func loadInternetPassword(for key: InternetPasswordKey) throws -> String {
        let identity = InternetPasswordIdentity(
            server: key.server,
            account: key.account,
            port: key.port,
            path: key.path,
            internetProtocol: key.protocol,
            authenticationType: key.authenticationType,
            accessGroup: key.accessGroup
        )
        guard let record = internetPasswords[identity] else {
            throw KeychainError.itemNotFound
        }
        return record.password
    }

    /// Removes an internet password.
    public func deleteInternetPassword(for key: InternetPasswordKey) throws {
        let identity = InternetPasswordIdentity(
            server: key.server,
            account: key.account,
            port: key.port,
            path: key.path,
            internetProtocol: key.protocol,
            authenticationType: key.authenticationType,
            accessGroup: key.accessGroup
        )
        internetPasswords.removeValue(forKey: identity)
        notify(service: key.server, account: key.account, accessGroup: key.accessGroup, kind: .deleted)
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

        private enum MutationKind: Sendable {
            case saved
            case updated
            case deleted
            case bulkDeleted
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
            for observer in observers.values
            where observer.service == service
                && (observer.accessGroup == nil || observer.accessGroup == accessGroup)
            {
                observer.continuation.yield(event)
            }
        }
    #else
        private enum MutationKind: Sendable {
            case saved
            case updated
            case deleted
            case bulkDeleted
        }

        private func notify(service: String, account: String?, accessGroup: String?, kind: MutationKind) {}
    #endif

    #if Cryptography
        private var cryptoKeys: [CryptoKeyReference<StoredSecKey>: StoredSecKey] = [:]

        /// Saves a cryptographic key.
        ///
        /// Replaces any previously saved key for the same `keyRef`.
        public func saveCryptoKey(_ key: StoredSecKey, for keyRef: CryptoKeyReference<StoredSecKey>) throws {
            cryptoKeys[keyRef] = key
        }

        /// Loads a cryptographic key.
        ///
        /// - Throws: `KeychainError.itemNotFound` if no key matching `keyRef` was saved.
        public func loadCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws -> StoredSecKey {
            guard let key = cryptoKeys[keyRef] else {
                throw KeychainError.itemNotFound
            }
            return key
        }

        /// Removes a cryptographic key.
        public func deleteCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws {
            cryptoKeys.removeValue(forKey: keyRef)
        }
    #endif

    private func matchesGenericPassword(_ key: GenericPasswordIdentity, query: KeychainDeleteQuery) -> Bool {
        if let service = query.service, key.service != service { return false }
        if let accessGroup = query.accessGroup, key.accessGroup != accessGroup { return false }
        if query.onlySynchronizable {
            return key.isSynchronizable
        }
        if query.includeSynchronizable {
            return true
        }
        return key.isSynchronizable == false
    }

    private func matchesInternetPassword(_ key: InternetPasswordIdentity, query: KeychainDeleteQuery) -> Bool {
        if let service = query.service, key.server != service { return false }
        if let accessGroup = query.accessGroup, key.accessGroup != accessGroup { return false }
        return query.includeSynchronizable || query.onlySynchronizable == false
    }
}
