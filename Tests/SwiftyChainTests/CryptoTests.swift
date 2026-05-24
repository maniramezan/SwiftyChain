#if Cryptography
    import Foundation
    import Security
    import Testing
    import SwiftyChain
    import SwiftyChainTesting

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
