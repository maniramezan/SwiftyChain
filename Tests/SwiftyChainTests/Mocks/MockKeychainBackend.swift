import Foundation
import Security
@testable import SwiftyChain

final class MockKeychainStore: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [KeychainQuery: Data] = [:]
    #if Cryptography
        private var cryptoKeys: [CryptoKeyQuery: SecKey] = [:]
    #endif

    func add(_ query: KeychainQuery, data: Data) throws {
        let error: KeychainError? = lock.withLock {
            if items.keys.contains(where: { $0.identityMatches(query) }) {
                return KeychainError.duplicateItem
            }
            items[query] = data
            return nil
        }
        if let error {
            throw error
        }
    }

    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        try lock.withLock {
            if query.matchLimit == .all {
                let matches = items.keys.filter { $0.matches(query) }.map { key in
                    KeychainQueryResult.attributes([.account(key.account ?? "")])
                }
                return .items(matches)
            }
            guard let item = items.first(where: { $0.key.matches(query) }) else {
                throw KeychainError.itemNotFound
            }
            return query.returnData ? .data(item.value) : .attributes([])
        }
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        try lock.withLock {
            guard let key = items.keys.first(where: { $0.matches(query) }) else {
                throw KeychainError.itemNotFound
            }
            if let data = attributes.data {
                items[key] = data
            }
        }
    }

    func delete(matching query: KeychainQuery) {
        lock.withLock {
            let keys = items.keys.filter { $0.matches(query) }
            for key in keys {
                items.removeValue(forKey: key)
            }
        }
    }

    #if Cryptography
        func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery) throws {
            try lock.withLock {
                if cryptoKeys[query] != nil {
                    throw KeychainError.duplicateItem
                }
                cryptoKeys[query] = key
            }
        }

        func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey {
            try lock.withLock {
                guard let key = cryptoKeys[query] else {
                    throw KeychainError.itemNotFound
                }
                return key
            }
        }

        func deleteCryptoKey(query: CryptoKeyQuery) throws {
            lock.withLock {
                _ = cryptoKeys.removeValue(forKey: query)
            }
        }
    #endif
}

struct MockKeychainBackend: SecureStorageBackend {
    let store: MockKeychainStore

    init(store: MockKeychainStore = MockKeychainStore()) {
        self.store = store
    }

    func add(_ query: KeychainQuery, data: Data) throws {
        try store.add(query, data: data)
    }

    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        try store.copyMatching(query)
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        try store.update(matching: query, to: attributes)
    }

    func delete(matching query: KeychainQuery) throws {
        store.delete(matching: query)
    }
}

#if Cryptography
    extension MockKeychainBackend: CryptoStorageBackend {
        func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery) throws {
            try store.addCryptoKey(key, query: query)
        }

        func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey {
            try store.loadCryptoKey(query: query)
        }

        func deleteCryptoKey(query: CryptoKeyQuery) throws {
            try store.deleteCryptoKey(query: query)
        }
    }
#endif

extension KeychainQuery {
    fileprivate func matches(_ other: KeychainQuery) -> Bool {
        if itemClass != other.itemClass { return false }
        if let service = other.service, self.service != service { return false }
        if let account = other.account, self.account != account { return false }
        if let accessGroup = other.accessGroup, self.accessGroup != accessGroup { return false }
        if let isSynchronizable = other.isSynchronizable, self.isSynchronizable != isSynchronizable { return false }
        if let server = other.server, self.server != server { return false }
        if let port = other.port, self.port != port { return false }
        if let path = other.path, self.path != path { return false }
        if let internetProtocol = other.internetProtocol, self.internetProtocol != internetProtocol { return false }
        if let authenticationType = other.authenticationType, self.authenticationType != authenticationType {
            return false
        }
        return true
    }

    // Matches the way Apple's keychain decides identity: same class + service
    // + account + accessGroup + synchronizable means the same item, regardless
    // of label/comment/accessibility differences.
    fileprivate func identityMatches(_ other: KeychainQuery) -> Bool {
        itemClass == other.itemClass
            && service == other.service
            && account == other.account
            && accessGroup == other.accessGroup
            && (isSynchronizable ?? false) == (other.isSynchronizable ?? false)
            && server == other.server
            && port == other.port
            && path == other.path
            && internetProtocol == other.internetProtocol
            && authenticationType == other.authenticationType
    }
}
