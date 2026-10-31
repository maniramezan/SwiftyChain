import Foundation
import SwiftyChain
import Synchronization

#if Cryptography && canImport(Security)
    import Security
#endif

/// A ``SecureStorageBackend`` that keeps items in memory.
///
/// It follows the same matching rules as the platform backends: a `nil` query
/// attribute matches any stored value, and a query that leaves `isSynchronizable`
/// unset matches both synchronizable and local items. `InMemoryKeychain` and
/// `InMemoryKeychainBackend` run the shared ``KeychainEngine`` over it, so tests
/// exercise the same logic as production.
package final class InMemoryStorageBackend: SecureStorageBackend, Sendable {
    private struct Item: Sendable {
        let itemClass: KeychainItemClass
        let service: String?
        let account: String?
        let accessGroup: String?
        let isSynchronizable: Bool
        let server: String?
        let port: Int?
        let path: String?
        let internetProtocol: InternetProtocol?
        let authenticationType: AuthenticationType?
        var accessibility: KeychainAccessibility?
        var label: String?
        var comment: String?
        var data: Data

        func hasSameIdentity(as other: Item) -> Bool {
            itemClass == other.itemClass
                && service == other.service
                && account == other.account
                && accessGroup == other.accessGroup
                && isSynchronizable == other.isSynchronizable
                && server == other.server
                && port == other.port
                && path == other.path
                && internetProtocol == other.internetProtocol
                && authenticationType == other.authenticationType
        }

        func matches(_ query: KeychainQuery) -> Bool {
            itemClass == query.itemClass
                && Self.matches(service, query.service)
                && Self.matches(account, query.account)
                && Self.matches(accessGroup, query.accessGroup)
                && Self.matches(isSynchronizable, query.isSynchronizable)
                && Self.matches(server, query.server)
                && Self.matches(port, query.port)
                && Self.matches(path, query.path)
                && Self.matches(internetProtocol, query.internetProtocol)
                && Self.matches(authenticationType, query.authenticationType)
        }

        var attributes: [KeychainAttribute] {
            [account.map(KeychainAttribute.account), service.map(KeychainAttribute.service)].compactMap { $0 }
        }

        private static func matches<Value: Equatable>(_ stored: Value?, _ requested: Value?) -> Bool {
            guard let requested else { return true }
            return stored == requested
        }
    }

    package let capabilities: SecureStorageCapabilities = .all

    private let items = Mutex<[Item]>([])

    package init() {}

    package func add(_ query: KeychainQuery, data: Data) throws {
        let item = Item(
            itemClass: query.itemClass,
            service: query.service,
            account: query.account,
            accessGroup: query.accessGroup,
            isSynchronizable: query.isSynchronizable ?? false,
            server: query.server,
            port: query.port,
            path: query.path,
            internetProtocol: query.internetProtocol,
            authenticationType: query.authenticationType,
            accessibility: query.accessibility,
            label: query.label,
            comment: query.comment,
            data: data
        )
        try items.withLock { items in
            if items.contains(where: { $0.hasSameIdentity(as: item) }) {
                throw KeychainError.duplicateItem
            }
            items.append(item)
        }
    }

    package func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        let matches = items.withLock { items in items.filter { $0.matches(query) } }
        guard let first = matches.first else {
            throw KeychainError.itemNotFound
        }
        if query.matchLimit == .all {
            return .items(matches.map { .attributes($0.attributes) })
        }
        if query.returnData {
            return .data(first.data)
        }
        if query.returnAttributes {
            return .attributes(first.attributes)
        }
        return .attributes([])
    }

    package func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        try items.withLock { items in
            let indices = items.indices.filter { items[$0].matches(query) }
            guard !indices.isEmpty else {
                throw KeychainError.itemNotFound
            }
            for index in indices {
                if let data = attributes.data {
                    items[index].data = data
                }
                if let label = attributes.label {
                    items[index].label = label
                }
                if let comment = attributes.comment {
                    items[index].comment = comment
                }
                if let accessibility = attributes.accessibility {
                    items[index].accessibility = accessibility
                }
            }
        }
    }

    package func delete(matching query: KeychainQuery) throws {
        items.withLock { items in items.removeAll { $0.matches(query) } }
    }

    #if Cryptography && canImport(Security)
        private struct CryptoIdentity: Hashable, Sendable {
            let tag: String
            let accessGroup: String?
        }

        private let cryptoKeys = Mutex<[CryptoIdentity: StoredSecKey]>([:])
    #endif
}

#if Cryptography && canImport(Security)
    extension InMemoryStorageBackend: CryptoStorageBackend {
        package func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery) throws {
            let identity = CryptoIdentity(tag: query.tag, accessGroup: query.accessGroup)
            try cryptoKeys.withLock { keys in
                if keys[identity] != nil {
                    throw KeychainError.duplicateItem
                }
                keys[identity] = StoredSecKey(key)
            }
        }

        package func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey {
            let identity = CryptoIdentity(tag: query.tag, accessGroup: query.accessGroup)
            guard let stored = cryptoKeys.withLock({ $0[identity] }) else {
                throw KeychainError.itemNotFound
            }
            return stored.rawValue
        }

        package func deleteCryptoKey(query: CryptoKeyQuery) throws {
            let identity = CryptoIdentity(tag: query.tag, accessGroup: query.accessGroup)
            cryptoKeys.withLock { _ = $0.removeValue(forKey: identity) }
        }
    }
#endif
