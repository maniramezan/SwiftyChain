import Foundation

@testable import SwiftyChain

final class MockKeychainStore: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [KeychainQuery: Data] = [:]

    func add(_ query: KeychainQuery, data: Data) throws {
        let error: KeychainError? = lock.withLock {
            if items[query] != nil {
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
}
