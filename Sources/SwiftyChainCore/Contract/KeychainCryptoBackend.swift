#if Cryptography && canImport(Security)
    import Security

    /// Selects a cryptographic key stored by a ``KeychainCryptoBackend``.
    public struct CryptoKeyQuery: Sendable, Hashable {
        /// The private application tag (`kSecAttrApplicationTag`) that identifies the key.
        public let tag: String
        /// The access group the key belongs to, or `nil` to match any.
        public let accessGroup: String?

        public init(tag: String, accessGroup: String? = nil) {
            self.tag = tag
            self.accessGroup = accessGroup
        }
    }

    /// The values stored with a new cryptographic key. A `nil` value stores the platform default.
    public struct CryptoKeyAttributes: Sendable, Hashable {
        /// When the key can be used.
        public let accessibility: KeychainAccessibility?

        public init(accessibility: KeychainAccessibility? = nil) {
            self.accessibility = accessibility
        }
    }

    /// A ``KeychainBackend`` that also stores `SecKey` values, available with the
    /// `cryptography` trait on platforms with the Security framework.
    ///
    /// Keys use their own requirements because `SecKey` is neither `Sendable` nor
    /// `Hashable`. A backend that conforms declares ``KeychainBackendCapabilities/cryptoKeys``.
    public protocol KeychainCryptoBackend: KeychainBackend {
        /// Stores a new key.
        ///
        /// - Throws: ``KeychainError/duplicateItem`` when a key with the same tag and
        ///   access group exists.
        func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery, attributes: CryptoKeyAttributes) throws

        /// Returns the matching key.
        ///
        /// - Throws: ``KeychainError/itemNotFound`` when no key matches.
        func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey

        /// Removes the matching key. Succeeds when no key matches.
        func deleteCryptoKey(query: CryptoKeyQuery) throws

        /// Removes every key in `accessGroup`, or every key the backend can reach when
        /// `accessGroup` is `nil`. Succeeds when no key matches.
        func deleteAllCryptoKeys(accessGroup: String?) throws
    }
#endif
