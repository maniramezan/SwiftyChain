#if Cryptography
    import Foundation
    import Security
    import Testing
    import SwiftyChainTesting

    @testable import SwiftyChain

    private struct NonCryptoSecureStorageBackend: SecureStorageBackend {
        func add(_ query: KeychainQuery, data: Data) throws {}

        func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
            .attributes([])
        }

        func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {}

        func delete(matching query: KeychainQuery) throws {}
    }

    private final class MockCryptoSecureStorageBackend: SecureStorageBackend, CryptoStorageBackend,
        @unchecked Sendable
    {
        private var storedKeys: [String: SecKey] = [:]
        private(set) var deletedQueries: [CryptoKeyQuery] = []

        func add(_ query: KeychainQuery, data: Data) throws {}

        func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
            .attributes([])
        }

        func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {}

        func delete(matching query: KeychainQuery) throws {}

        func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery) throws {
            if storedKeys[query.tag] != nil {
                throw KeychainError.duplicateItem
            }
            storedKeys[query.tag] = key
        }

        func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey {
            guard let key = storedKeys[query.tag] else {
                throw KeychainError.itemNotFound
            }
            return key
        }

        func deleteCryptoKey(query: CryptoKeyQuery) throws {
            deletedQueries.append(query)
            guard storedKeys.removeValue(forKey: query.tag) != nil else {
                throw KeychainError.itemNotFound
            }
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
    func cryptoSaveOverwritesExistingTag() async throws {
        let keychain = InMemoryKeychain()
        let first = try makeECKey()
        let second = try makeECKey()
        let ref = CryptoKeyReference<StoredSecKey>(tag: "tests.crypto.overwrite")

        try await keychain.saveCryptoKey(StoredSecKey(first), for: ref)
        try await keychain.saveCryptoKey(StoredSecKey(second), for: ref)

        let loaded = try await keychain.loadCryptoKey(keyRef: ref)
        #expect(CFEqual(loaded.rawValue, second))
    }

    @Test
    func cryptoOperationsFailWithoutCryptoBackend() async throws {
        let keychain = Keychain(backend: NonCryptoSecureStorageBackend())
        let secKey = try makeECKey()
        let ref = CryptoKeyReference<StoredSecKey>(tag: "tests.crypto.unsupported")

        await #expect(throws: KeychainError.platformUnsupported("CryptoStorageBackend not available")) {
            try await keychain.saveCryptoKey(StoredSecKey(secKey), for: ref)
        }
        await #expect(throws: KeychainError.platformUnsupported("CryptoStorageBackend not available")) {
            _ = try await keychain.loadCryptoKey(keyRef: ref)
        }
        await #expect(throws: KeychainError.platformUnsupported("CryptoStorageBackend not available")) {
            try await keychain.deleteCryptoKey(keyRef: ref)
        }
    }

    @Test
    func cryptoActorRoundTripsThroughInjectedCryptoBackend() async throws {
        let backend = MockCryptoSecureStorageBackend()
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
        #expect(backend.deletedQueries.last?.accessibility == ref.accessibility)
    }

    @Test
    func cryptoActorOverwritesDuplicateKeyViaDeleteAndReadd() async throws {
        let backend = MockCryptoSecureStorageBackend()
        let keychain = Keychain(backend: backend)
        let first = try makeECKey()
        let second = try makeECKey()
        let ref = CryptoKeyReference<StoredSecKey>(tag: "tests.crypto.injected.overwrite")

        try await keychain.saveCryptoKey(StoredSecKey(first), for: ref)
        try await keychain.saveCryptoKey(StoredSecKey(second), for: ref)

        let loaded = try await keychain.loadCryptoKey(keyRef: ref)
        #expect(CFEqual(loaded.rawValue, second))
        #expect(backend.deletedQueries.map(\.tag) == [ref.tag])
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
