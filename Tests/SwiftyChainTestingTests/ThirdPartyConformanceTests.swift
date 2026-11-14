import Foundation
import SwiftyChain
import SwiftyChainTesting
import Synchronization
import Testing

// A conformance written the way a downstream package would, without
// `@testable`. It must compile under every trait combination: enabling
// `observation` or `cryptography` may not add requirements to KeychainProtocol.
private actor DictionaryKeychain: KeychainProtocol {
    private var items: [String: Data] = [:]
    private var internetPasswords: [String: String] = [:]

    private func id(service: String, account: String) -> String {
        "\(service)/\(account)"
    }

    private func id(for key: InternetPasswordKey) -> String {
        "\(key.server)/\(key.account)"
    }

    func save<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        let itemID = id(service: key.service, account: key.account)
        guard items[itemID] == nil else { throw KeychainError.duplicateItem }
        items[itemID] = try value.keychainData()
    }

    func load<T: KeychainStorable>(key: KeychainKey<T>) throws -> T {
        guard let data = items[id(service: key.service, account: key.account)] else {
            throw KeychainError.itemNotFound
        }
        return try T.fromKeychainData(data)
    }

    func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T? {
        try items[id(service: key.service, account: key.account)].map(T.fromKeychainData)
    }

    func update<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        let itemID = id(service: key.service, account: key.account)
        guard items[itemID] != nil else { throw KeychainError.itemNotFound }
        items[itemID] = try value.keychainData()
    }

    func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        items[id(service: key.service, account: key.account)] = try value.keychainData()
    }

    func delete<T: KeychainStorable>(key: KeychainKey<T>) throws {
        items.removeValue(forKey: id(service: key.service, account: key.account))
    }

    func deleteAll(service: String, accessGroup: String?) throws {
        items = items.filter { !$0.key.hasPrefix("\(service)/") }
    }

    func deleteAllSynchronizable(service: String, accessGroup: String?) throws {}

    func deleteAllItems(matching query: KeychainDeleteQuery) throws {
        guard let service = query.service else {
            items.removeAll()
            return
        }
        try deleteAll(service: service, accessGroup: query.accessGroup)
    }

    func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool {
        items[id(service: key.service, account: key.account)] != nil
    }

    func allAccounts(service: String, accessGroup: String?) throws -> [String] {
        items.keys.compactMap { itemID in
            itemID.hasPrefix("\(service)/") ? String(itemID.dropFirst(service.count + 1)) : nil
        }
    }

    func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws {
        internetPasswords[id(for: key)] = password
    }

    func loadInternetPassword(for key: InternetPasswordKey) throws -> String {
        guard let password = internetPasswords[id(for: key)] else { throw KeychainError.itemNotFound }
        return password
    }

    func deleteInternetPassword(for key: InternetPasswordKey) throws {
        internetPasswords.removeValue(forKey: id(for: key))
    }
}

@Test
func thirdPartyConformanceOnlyNeedsCoreRequirements() async throws {
    let keychain: any KeychainProtocol = DictionaryKeychain()
    let key = KeychainKey<String>(service: "tests.third-party", account: "token")
    try await keychain.upsert("value", for: key)
    #expect(try await keychain.load(key: key) == "value")
    #expect(try await keychain.allAccounts(service: "tests.third-party") == ["token"])
}

private final class DownstreamBackend: KeychainBackend {
    let capabilities = InMemoryKeychainBackend.defaultCapabilities
    private let storage = InMemoryKeychainBackend()
    private let policies = Mutex<[KeychainAttributes]>([])

    var writtenPolicies: [KeychainAttributes] { policies.withLock { $0 } }

    func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {
        try storage.add(query, attributes: attributes)
        policies.withLock { $0.append(attributes) }
    }

    func data(matching query: KeychainQuery) throws -> Data { try storage.data(matching: query) }
    func contains(matching query: KeychainQuery) throws -> Bool { try storage.contains(matching: query) }
    func accounts(matching query: KeychainQuery) throws -> [String] { try storage.accounts(matching: query) }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        try storage.update(matching: query, to: attributes)
        policies.withLock { $0.append(attributes) }
    }

    func delete(matching query: KeychainQuery) throws { try storage.delete(matching: query) }
}

@Test
func downstreamBackendRunsThroughThePublicEngine() async throws {
    let backend = DownstreamBackend()
    let keychain = Keychain(backend: backend)
    let policy = KeychainKey<String>(service: "tests.downstream", account: "token", accessibility: .afterFirstUnlock)
    let plain = KeychainKey<String>(service: policy.service, account: policy.account)
    try await keychain.save("first", for: policy)
    try await keychain.upsert("second", for: plain)
    #expect(try await keychain.load(key: plain) == "second")
    #expect(try await keychain.allAccounts(service: plain.service) == [plain.account])
    #expect(backend.writtenPolicies.map(\.accessibility) == [.afterFirstUnlock, nil])
    let storage = KeychainStorage<String>(plain.account, service: plain.service, backend: backend)
    storage.wrappedValue = "third"
    #expect(storage.projectedValue == nil)
    #expect(try await keychain.load(key: plain) == "third")
    #expect(backend.writtenPolicies.last?.accessibility == nil)
    try await keychain.deleteAll(service: plain.service)
    #expect(try await keychain.exists(key: plain) == false)
}
