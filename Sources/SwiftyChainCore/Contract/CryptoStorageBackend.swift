#if Cryptography && canImport(Security)
    import Security

    /// Query descriptor for cryptographic key operations.
    package struct CryptoKeyQuery: Sendable, Hashable {
        package let tag: String
        package let accessGroup: String?
        package let accessibility: KeychainAccessibility?

        package init(tag: String, accessGroup: String?, accessibility: KeychainAccessibility?) {
            self.tag = tag
            self.accessGroup = accessGroup
            self.accessibility = accessibility
        }
    }

    /// Backend contract for `SecKey` storage, separate from ``SecureStorageBackend``
    /// because `SecKey` is not `Sendable` or `Hashable` and cannot flow through
    /// ``KeychainQuery``. Backends that conform declare
    /// ``SecureStorageCapabilities/cryptoKeys``.
    package protocol CryptoStorageBackend: SecureStorageBackend {
        func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery) throws
        func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey
        func deleteCryptoKey(query: CryptoKeyQuery) throws
    }
#endif
