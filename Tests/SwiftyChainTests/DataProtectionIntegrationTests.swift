#if canImport(Security) && !os(tvOS)
    import Foundation
    import Security
    import Testing

    #if canImport(LocalAuthentication)
        import LocalAuthentication
    #endif

    import SwiftyChain

    /// Runs against the real data-protection keychain.
    ///
    /// iOS, watchOS, and visionOS always use that store, so `SWIFTYCHAIN_RUN_KEYCHAIN_INTEGRATION`
    /// enables these tests there. On macOS the store needs a signed, entitled host, so it
    /// takes its own `SWIFTYCHAIN_RUN_DATA_PROTECTION_INTEGRATION` flag.
    private let dataProtectionIntegrationEnabled: Bool = {
        let environment = ProcessInfo.processInfo.environment
        #if os(macOS)
            return environment["SWIFTYCHAIN_RUN_DATA_PROTECTION_INTEGRATION"] == "1"
        #else
            return environment["SWIFTYCHAIN_RUN_KEYCHAIN_INTEGRATION"] == "1"
        #endif
    }()

    @Suite("Data-protection keychain", .enabled(if: dataProtectionIntegrationEnabled), .serialized)
    struct DataProtectionIntegrationTests {
        private let keychain = Keychain(configuration: .init(macOSStore: .dataProtection))

        @Test(.timeLimit(.minutes(1)))
        func addingAccessControlKeepsTheStoredAccessibility() async throws {
            let service = "dev.manman.SwiftyChain.integration.access-control.\(UUID().uuidString)"
            let stored = KeychainKey<String>(service: service, account: "token", accessibility: .afterFirstUnlock)
            let protected = KeychainKey<String>(service: service, account: "token", accessControl: .userPresence)
            do {
                try await keychain.save("value", for: stored)
                #expect(try hasItem(service: service, protection: kSecAttrAccessibleAfterFirstUnlock))

                try await keychain.update("value", for: protected)

                // macOS won't show an access-controlled item's attributes without
                // authentication, so the protection class is checked by matching on it.
                #expect(try hasItem(service: service, protection: kSecAttrAccessibleAfterFirstUnlock))
                #expect(try !hasItem(service: service, protection: kSecAttrAccessibleWhenUnlocked))
                try await keychain.delete(key: stored)
            } catch {
                try? await keychain.delete(key: stored)
                throw error
            }
        }

        #if Cryptography
            @Test(.timeLimit(.minutes(1)))
            func cryptoUpsertRejectsADifferentKeyTypeAndKeepsTheOriginal() async throws {
                let ref = CryptoKeyReference<StoredSecKey>(
                    tag: "dev.manman.SwiftyChain.integration.crypto.\(UUID().uuidString)")
                let original = try makeKey(type: kSecAttrKeyTypeECSECPrimeRandom, bits: 256)
                let replacement = try makeKey(type: kSecAttrKeyTypeECSECPrimeRandom, bits: 256)
                do {
                    try await keychain.upsertCryptoKey(StoredSecKey(original), for: ref)
                    await #expect(throws: KeychainError.duplicateItem) {
                        try await keychain.saveCryptoKey(StoredSecKey(replacement), for: ref)
                    }

                    await #expect(
                        throws: KeychainError.invalidArgument(
                            "The replacement key's type, class, or size differs from the stored key; delete the stored key first"
                        )
                    ) {
                        try await keychain.upsertCryptoKey(
                            StoredSecKey(try makeKey(type: kSecAttrKeyTypeRSA, bits: 2048)), for: ref)
                    }
                    #expect(try await externalRepresentation(of: ref) == externalRepresentation(of: original))

                    try await keychain.upsertCryptoKey(StoredSecKey(replacement), for: ref)
                    #expect(try await externalRepresentation(of: ref) == externalRepresentation(of: replacement))
                    try await keychain.deleteCryptoKey(keyRef: ref)
                } catch {
                    try? await keychain.deleteCryptoKey(keyRef: ref)
                    throw error
                }
            }

            /// Saving over a key with access control must report a duplicate without
            /// prompting, even though the existing key can't be read without authentication.
            @Test(.timeLimit(.minutes(1)))
            func cryptoSaveDetectsAnAccessControlledDuplicateWithoutPrompting() async throws {
                let ref = CryptoKeyReference<StoredSecKey>(
                    tag: "dev.manman.SwiftyChain.integration.crypto.acl.\(UUID().uuidString)",
                    accessibility: .afterFirstUnlock,
                    accessControl: .userPresence)
                do {
                    try await keychain.saveCryptoKey(
                        StoredSecKey(try makeKey(type: kSecAttrKeyTypeECSECPrimeRandom, bits: 256)), for: ref)
                    await #expect(throws: KeychainError.duplicateItem) {
                        try await keychain.saveCryptoKey(
                            StoredSecKey(try makeKey(type: kSecAttrKeyTypeECSECPrimeRandom, bits: 256)), for: ref)
                    }
                    try await keychain.deleteCryptoKey(keyRef: ref)
                } catch {
                    try? await keychain.deleteCryptoKey(keyRef: ref)
                    throw error
                }
            }

            private func externalRepresentation(of ref: CryptoKeyReference<StoredSecKey>) async throws -> Data? {
                externalRepresentation(of: try await keychain.loadCryptoKey(keyRef: ref).rawValue)
            }

            private func externalRepresentation(of key: SecKey) -> Data? {
                SecKeyCopyExternalRepresentation(key, nil) as Data?
            }

            private func makeKey(type: CFString, bits: Int) throws -> SecKey {
                let attributes: [String: Any] = [
                    kSecAttrKeyType as String: type,
                    kSecAttrKeySizeInBits as String: bits,
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

        /// Whether an item for `service` has `protection`, checked without reading it or
        /// prompting: an access-controlled match reports `errSecInteractionNotAllowed`.
        private func hasItem(service: String, protection: CFString) throws -> Bool {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccessible as String: protection,
            ]
            #if os(macOS)
                query[kSecUseDataProtectionKeychain as String] = true
            #endif
            #if canImport(LocalAuthentication)
                let context = LAContext()
                context.interactionNotAllowed = true
                query[kSecUseAuthenticationContext as String] = context
            #endif
            let status = SecItemCopyMatching(query as CFDictionary, nil)
            try #require(
                [errSecSuccess, errSecInteractionNotAllowed, errSecItemNotFound].contains(status),
                "SecItemCopyMatching returned \(status)")
            return status != errSecItemNotFound
        }
    }
#endif
