/// Public protocol for depending on keychain behavior in application code.
///
/// ``Keychain`` conforms to this protocol.
///
/// The separate `SwiftyChainTesting` product provides in-memory implementations
/// for downstream tests.
public protocol KeychainProtocol: Actor, Sendable {
    func save<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws
    func load<T: KeychainStorable>(key: KeychainKey<T>) throws -> T
    func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T?
    func update<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws
    func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws
    func delete<T: KeychainStorable>(key: KeychainKey<T>) throws
    func deleteAll(service: String, accessGroup: String?) throws
    func deleteAllSynchronizable(service: String, accessGroup: String?) throws
    func deleteAllItems(matching query: KeychainDeleteQuery) throws
    func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool
    func allAccounts(service: String, accessGroup: String?) throws -> [String]
    func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws
    func loadInternetPassword(for key: InternetPasswordKey) throws -> String
    func deleteInternetPassword(for key: InternetPasswordKey) throws
    #if Observation
        func observeKeychainChanges(
            service: String,
            accessGroup: String?
        ) -> AsyncStream<KeychainChangeEvent>
    #endif
    #if Cryptography
        func saveCryptoKey(_ key: StoredSecKey, for keyRef: CryptoKeyReference<StoredSecKey>) throws
        func loadCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws -> StoredSecKey
        func deleteCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws
    #endif
}

public extension KeychainProtocol {
    func deleteAll(service: String) throws {
        try deleteAll(service: service, accessGroup: nil)
    }

    func deleteAllSynchronizable(service: String) throws {
        try deleteAllSynchronizable(service: service, accessGroup: nil)
    }

    func allAccounts(service: String) throws -> [String] {
        try allAccounts(service: service, accessGroup: nil)
    }

    #if Observation
        func observeKeychainChanges(service: String) -> AsyncStream<KeychainChangeEvent> {
            observeKeychainChanges(service: service, accessGroup: nil)
        }
    #endif
}
