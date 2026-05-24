import Foundation
import SwiftyChain

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

    public init() {}

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
        notify(service: key.service, account: key.account, kind: .saved)
    }

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

    public func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T? {
        do {
            return try load(key: key)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

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
        notify(service: key.service, account: key.account, kind: .updated)
    }

    public func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        do {
            try save(value, for: key)
        } catch KeychainError.duplicateItem {
            try update(value, for: key)
        }
    }

    public func delete<T: KeychainStorable>(key: KeychainKey<T>) throws {
        let identity = GenericPasswordIdentity(
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable
        )
        genericPasswords.removeValue(forKey: identity)
        notify(service: key.service, account: key.account, kind: .deleted)
    }

    public func deleteAll(service: String, accessGroup: String? = nil) throws {
        try deleteAllItems(matching: .allItems(service: service, accessGroup: accessGroup))
    }

    public func deleteAllSynchronizable(service: String, accessGroup: String? = nil) throws {
        try deleteAllItems(matching: .synchronizableItems(service: service, accessGroup: accessGroup))
    }

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
            notify(service: service, account: nil, kind: .bulkDeleted)
        }
    }

    public func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool {
        let identity = GenericPasswordIdentity(
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable
        )
        return genericPasswords[identity] != nil
    }

    public func allAccounts(service: String, accessGroup: String? = nil) throws -> [String] {
        genericPasswords.keys.compactMap { key in
            guard key.service == service else { return nil }
            guard accessGroup == nil || key.accessGroup == accessGroup else { return nil }
            return key.account
        }
    }

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
        notify(service: key.server, account: key.account, kind: .saved)
    }

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
        notify(service: key.server, account: key.account, kind: .deleted)
    }

    #if Observation
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

        private func notify(service: String, account: String?, kind: MutationKind) {
            let eventKind: KeychainChangeEvent.Kind = switch kind {
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
        private enum MutationKind: Sendable {
            case saved
            case updated
            case deleted
            case bulkDeleted
        }

        private func notify(service: String, account: String?, kind: MutationKind) {}
    #endif

    #if Cryptography
        private var cryptoKeys: [CryptoKeyReference<StoredSecKey>: StoredSecKey] = [:]

        public func saveCryptoKey(_ key: StoredSecKey, for keyRef: CryptoKeyReference<StoredSecKey>) throws {
            cryptoKeys[keyRef] = key
        }

        public func loadCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws -> StoredSecKey {
            guard let key = cryptoKeys[keyRef] else {
                throw KeychainError.itemNotFound
            }
            return key
        }

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
