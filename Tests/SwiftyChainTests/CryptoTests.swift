#if Cryptography && canImport(Security)
    import Foundation
    import Security
    import Testing
    import SwiftyChainTesting

    @testable import SwiftyChain

    private final class MockCryptoBackend: KeychainCryptoBackend, @unchecked Sendable {
        let capabilities: KeychainBackendCapabilities = .all

        private var storedKeys: [String: SecKey] = [:]
        private(set) var deletedQueries: [CryptoKeyQuery] = []
        private(set) var addedAttributes: [CryptoKeyAttributes] = []

        func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {}
        func data(matching query: KeychainQuery) throws -> Data { throw KeychainError.itemNotFound }
        func contains(matching query: KeychainQuery) throws -> Bool { false }
        func accounts(matching query: KeychainQuery) throws -> [String] { [] }
        func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {}
        func delete(matching query: KeychainQuery) throws {}

        func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery, attributes: CryptoKeyAttributes) throws {
            if storedKeys[query.tag] != nil {
                throw KeychainError.duplicateItem
            }
            storedKeys[query.tag] = key
            addedAttributes.append(attributes)
        }

        func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey {
            guard let key = storedKeys[query.tag] else {
                throw KeychainError.itemNotFound
            }
            return key
        }

        func deleteCryptoKey(query: CryptoKeyQuery) throws {
            deletedQueries.append(query)
            storedKeys.removeValue(forKey: query.tag)
        }

        private(set) var bulkDeletedAccessGroups: [String?] = []

        func deleteAllCryptoKeys(accessGroup: String?) throws {
            bulkDeletedAccessGroups.append(accessGroup)
            storedKeys.removeAll()
        }
    }

    @Test
    func cryptoKeyRoundTripsThroughMockBackend() async throws {
        let keychain = InMemoryKeychain()
        let secKey = try makeECKey()
        let ref = CryptoKeyReference<StoredSecKey>(tag: "tests.crypto.roundtrip")

        try await keychain.saveCryptoKey(StoredSecKey(secKey), for: ref)
        let loaded = try await keychain.loadCryptoKey(keyRef: ref)
        #expect(loaded.rawValue === secKey || CFEqual(loaded.rawValue, secKey))

        try await keychain.deleteCryptoKey(keyRef: ref)
        await #expect(throws: KeychainError.itemNotFound) {
            _ = try await keychain.loadCryptoKey(keyRef: ref)
        }
    }

    @Test
    func cryptoSaveRejectsAnExistingTag() async throws {
        let keychain = InMemoryKeychain()
        let first = try makeECKey()
        let second = try makeECKey()
        let ref = CryptoKeyReference<StoredSecKey>(tag: "tests.crypto.overwrite")

        try await keychain.saveCryptoKey(StoredSecKey(first), for: ref)
        await #expect(throws: KeychainError.duplicateItem) {
            try await keychain.saveCryptoKey(StoredSecKey(second), for: ref)
        }

        let loaded = try await keychain.loadCryptoKey(keyRef: ref)
        #expect(CFEqual(loaded.rawValue, first))
    }

    @Test
    func cryptoBulkDeleteRoutesToTheCryptoBackend() async throws {
        let backend = MockCryptoBackend()
        let keychain = Keychain(backend: backend)
        try await keychain.saveCryptoKey(
            StoredSecKey(try makeECKey()),
            for: CryptoKeyReference<StoredSecKey>(tag: "tests.crypto.bulk")
        )

        try await keychain.deleteAllItems(
            matching: KeychainDeleteQuery(accessGroup: "group.a", itemClass: .cryptographicKey))
        try await keychain.deleteAllItems(matching: KeychainDeleteQuery(itemClass: .cryptographicKey))

        #expect(backend.bulkDeletedAccessGroups == ["group.a", nil])
        await #expect(throws: KeychainError.itemNotFound) {
            _ = try await keychain.loadCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>(tag: "tests.crypto.bulk"))
        }
    }

    @Test
    func cryptoBulkDeleteRejectsAService() async throws {
        let backend = MockCryptoBackend()
        let keychain = Keychain(backend: backend)

        await #expect(throws: KeychainError.self) {
            try await keychain.deleteAllItems(
                matching: KeychainDeleteQuery(service: "com.example", itemClass: .cryptographicKey)
            )
        }
        await #expect(throws: KeychainError.self) {
            try await keychain.deleteAllItems(
                matching: KeychainDeleteQuery(onlySynchronizable: true, itemClass: .cryptographicKey)
            )
        }
        #expect(backend.bulkDeletedAccessGroups.isEmpty)
    }

    @Test
    func cryptoOperationsFailWithoutCryptoBackend() async throws {
        let keychain = Keychain(backend: InMemoryKeychainBackend(capabilities: [.internetPasswords]))
        let secKey = try makeECKey()
        let ref = CryptoKeyReference<StoredSecKey>(tag: "tests.crypto.unsupported")

        await #expect(
            throws: KeychainError.platformUnsupported("Cryptographic keys are not supported by this keychain backend")
        ) {
            try await keychain.saveCryptoKey(StoredSecKey(secKey), for: ref)
        }
        await #expect(
            throws: KeychainError.platformUnsupported("Cryptographic keys are not supported by this keychain backend")
        ) {
            _ = try await keychain.loadCryptoKey(keyRef: ref)
        }
        await #expect(
            throws: KeychainError.platformUnsupported("Cryptographic keys are not supported by this keychain backend")
        ) {
            try await keychain.deleteCryptoKey(keyRef: ref)
        }
    }

    @Test
    func cryptoActorRoundTripsThroughInjectedCryptoBackend() async throws {
        let backend = MockCryptoBackend()
        let keychain = Keychain(backend: backend)
        let secKey = try makeECKey()
        let ref = CryptoKeyReference<StoredSecKey>(
            tag: "tests.crypto.injected.roundtrip",
            accessGroup: "group.tests.crypto",
            accessibility: .afterFirstUnlock
        )

        try await keychain.saveCryptoKey(StoredSecKey(secKey), for: ref)

        let loaded = try await keychain.loadCryptoKey(keyRef: ref)
        #expect(CFEqual(loaded.rawValue, secKey))

        try await keychain.deleteCryptoKey(keyRef: ref)
        await #expect(throws: KeychainError.itemNotFound) {
            _ = try await keychain.loadCryptoKey(keyRef: ref)
        }

        #expect(backend.deletedQueries.last?.tag == ref.tag)
        #expect(backend.deletedQueries.last?.accessGroup == ref.accessGroup)
        #expect(backend.addedAttributes.last?.accessibility == ref.accessibility)
    }

    @Test
    func cryptoSaveNeverDeletesAnExistingKey() async throws {
        let backend = MockCryptoBackend()
        let keychain = Keychain(backend: backend)
        let first = try makeECKey()
        let ref = CryptoKeyReference<StoredSecKey>(tag: "tests.crypto.injected.overwrite")

        try await keychain.saveCryptoKey(StoredSecKey(first), for: ref)
        await #expect(throws: KeychainError.duplicateItem) {
            try await keychain.saveCryptoKey(StoredSecKey(try makeECKey()), for: ref)
        }

        #expect(CFEqual(try await keychain.loadCryptoKey(keyRef: ref).rawValue, first))
        #expect(backend.deletedQueries.isEmpty)
    }

    @Test
    func cryptoKeyReferenceIdentityIgnoresAccessibility() {
        let whenUnlocked = CryptoKeyReference<StoredSecKey>(
            tag: "tests.crypto.identity",
            accessibility: .whenUnlocked
        )
        let afterFirstUnlock = CryptoKeyReference<StoredSecKey>(
            tag: "tests.crypto.identity",
            accessibility: .afterFirstUnlock
        )

        #expect(whenUnlocked == afterFirstUnlock)
        #expect(Set([whenUnlocked, afterFirstUnlock]).count == 1)
    }

    private func makeECKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw error
            }
            throw KeychainError.unexpectedData
        }
        return key
    }
#endif
