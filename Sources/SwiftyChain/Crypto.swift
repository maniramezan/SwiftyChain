#if Cryptography
    import Security

    public protocol CryptoKeyStorable: Sendable {}

    public struct StoredSecKey: CryptoKeyStorable, @unchecked Sendable {
        public let rawValue: SecKey

        public init(_ rawValue: SecKey) {
            self.rawValue = rawValue
        }
    }

    public struct CryptoKeyReference<Value: CryptoKeyStorable>: Sendable, Hashable {
        public let tag: String
        public let accessGroup: String?
        public let accessibility: KeychainAccessibility

        public init(
            tag: String,
            accessGroup: String? = nil,
            accessibility: KeychainAccessibility = .whenUnlocked
        ) {
            self.tag = tag
            self.accessGroup = accessGroup
            self.accessibility = accessibility
        }
    }

    extension Keychain {
        public func saveCryptoKey(_ key: StoredSecKey, for keyRef: CryptoKeyReference<StoredSecKey>) throws {
            guard let cryptoBackend = backend as? CryptoStorageBackend else {
                throw KeychainError.platformUnsupported("CryptoStorageBackend not available")
            }
            let query = CryptoKeyQuery(
                tag: keyRef.tag, accessGroup: keyRef.accessGroup, accessibility: keyRef.accessibility
            )
            do {
                try cryptoBackend.addCryptoKey(key.rawValue, query: query)
            } catch KeychainError.duplicateItem {
                try cryptoBackend.deleteCryptoKey(query: query)
                try cryptoBackend.addCryptoKey(key.rawValue, query: query)
            }
        }

        public func loadCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws -> StoredSecKey {
            guard let cryptoBackend = backend as? CryptoStorageBackend else {
                throw KeychainError.platformUnsupported("CryptoStorageBackend not available")
            }
            let secKey = try cryptoBackend.loadCryptoKey(
                query: CryptoKeyQuery(
                    tag: keyRef.tag, accessGroup: keyRef.accessGroup, accessibility: keyRef.accessibility
                )
            )
            return StoredSecKey(secKey)
        }

        public func deleteCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws {
            guard let cryptoBackend = backend as? CryptoStorageBackend else {
                throw KeychainError.platformUnsupported("CryptoStorageBackend not available")
            }
            try cryptoBackend.deleteCryptoKey(
                query: CryptoKeyQuery(
                    tag: keyRef.tag, accessGroup: keyRef.accessGroup, accessibility: keyRef.accessibility
                )
            )
        }
    }
#endif
