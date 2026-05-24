#if Cryptography
    import Security

    /// A marker protocol for types that can be stored as cryptographic keys in the keychain.
    ///
    /// The built-in conforming type is ``StoredSecKey``. You can define additional
    /// conformances for other key representations and use them with ``CryptoKeyReference``.
    public protocol CryptoKeyStorable: Sendable {}

    /// A wrapper around `SecKey` that satisfies ``CryptoKeyStorable``.
    ///
    /// Use this type to persist and retrieve raw `SecKey` values via the keychain:
    ///
    /// ```swift
    /// let keyRef = CryptoKeyReference<StoredSecKey>(tag: "com.example.app.signing-key")
    /// try await Keychain.shared.saveCryptoKey(StoredSecKey(mySecKey), for: keyRef)
    /// let stored = try await Keychain.shared.loadCryptoKey(keyRef: keyRef)
    /// let secKey = stored.rawValue
    /// ```
    public struct StoredSecKey: CryptoKeyStorable, @unchecked Sendable {
        /// The underlying `SecKey` value.
        public let rawValue: SecKey

        /// Wraps a `SecKey` for keychain storage.
        ///
        /// - Parameter rawValue: The `SecKey` to wrap.
        public init(_ rawValue: SecKey) {
            self.rawValue = rawValue
        }
    }

    /// A typed descriptor for a cryptographic key stored in the keychain.
    ///
    /// Analogous to ``KeychainKey`` for generic passwords, `CryptoKeyReference` identifies
    /// a `SecKey` item by its private application tag and an optional access group.
    ///
    /// ```swift
    /// let keyRef = CryptoKeyReference<StoredSecKey>(
    ///     tag: "com.example.app.encryption-key",
    ///     accessibility: .afterFirstUnlock
    /// )
    /// ```
    public struct CryptoKeyReference<Value: CryptoKeyStorable>: Sendable, Hashable {
        /// The private application tag that identifies the key (`kSecAttrApplicationTag`).
        public let tag: String
        /// The access group for sharing across apps, or `nil` for the default group.
        public let accessGroup: String?
        /// The accessibility policy for this item.
        public let accessibility: KeychainAccessibility

        /// Creates a cryptographic key reference.
        ///
        /// - Parameters:
        ///   - tag: The private application tag (e.g., `"com.example.app.key-name"`).
        ///   - accessGroup: The keychain access group. Defaults to `nil`.
        ///   - accessibility: The accessibility policy. Defaults to ``KeychainAccessibility/whenUnlocked``.
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
        /// Saves a cryptographic key to the keychain, replacing any existing key with the same reference.
        ///
        /// If a key already exists for `keyRef` it is deleted and re-added, matching the
        /// upsert behavior of ``Keychain/upsert(_:for:)`` for generic passwords.
        ///
        /// - Parameters:
        ///   - key: The ``StoredSecKey`` wrapping the `SecKey` to persist.
        ///   - keyRef: The ``CryptoKeyReference`` identifying the item.
        /// - Throws: ``KeychainError/platformUnsupported(_:)`` if the crypto backend is unavailable,
        ///   or another ``KeychainError`` if the operation fails.
        ///
        /// ```swift
        /// try await Keychain.shared.saveCryptoKey(StoredSecKey(secKey), for: keyRef)
        /// ```
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

        /// Loads a cryptographic key from the keychain.
        ///
        /// - Parameter keyRef: The ``CryptoKeyReference`` identifying the item.
        /// - Returns: A ``StoredSecKey`` wrapping the stored `SecKey`.
        /// - Throws: ``KeychainError/itemNotFound`` if no key exists for the reference,
        ///   ``KeychainError/platformUnsupported(_:)`` if the crypto backend is unavailable,
        ///   or another ``KeychainError`` on failure.
        ///
        /// ```swift
        /// let stored = try await Keychain.shared.loadCryptoKey(keyRef: keyRef)
        /// let secKey = stored.rawValue
        /// ```
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

        /// Deletes a cryptographic key from the keychain.
        ///
        /// - Parameter keyRef: The ``CryptoKeyReference`` identifying the item to delete.
        /// - Throws: ``KeychainError/itemNotFound`` if no key exists for the reference,
        ///   ``KeychainError/platformUnsupported(_:)`` if the crypto backend is unavailable,
        ///   or another ``KeychainError`` on failure.
        ///
        /// ```swift
        /// try await Keychain.shared.deleteCryptoKey(keyRef: keyRef)
        /// ```
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
