#if Cryptography && canImport(Security)
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

        /// Two references identify the same key when their tag and access group match.
        /// Accessibility controls how a key is stored, not its keychain identity.
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.tag == rhs.tag && lhs.accessGroup == rhs.accessGroup
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(tag)
            hasher.combine(accessGroup)
        }
    }

    extension Keychain {
        /// Saves a new cryptographic key to the keychain.
        ///
        /// Like ``Keychain/save(_:for:)``, this never replaces an existing item. To replace
        /// a key, delete it with ``deleteCryptoKey(keyRef:)`` first. SwiftyChain has no
        /// crypto-key upsert: the keychain can't swap a key's material in place, so
        /// replacing one always means deleting it, and losing it if the new key can't be
        /// stored.
        ///
        /// - Parameters:
        ///   - key: The ``StoredSecKey`` wrapping the `SecKey` to persist.
        ///   - keyRef: The ``CryptoKeyReference`` identifying the item.
        /// - Throws: ``KeychainError/duplicateItem`` if a key already exists for `keyRef`,
        ///   ``KeychainError/platformUnsupported(_:)`` if the crypto backend is unavailable,
        ///   or another ``KeychainError`` if the operation fails.
        ///
        /// ```swift
        /// try await Keychain.shared.saveCryptoKey(StoredSecKey(secKey), for: keyRef)
        /// ```
        public func saveCryptoKey(_ key: StoredSecKey, for keyRef: CryptoKeyReference<StoredSecKey>) throws {
            try engine.saveCryptoKey(key, for: keyRef)
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
            try engine.loadCryptoKey(keyRef: keyRef)
        }

        /// Deletes a cryptographic key from the keychain.
        ///
        /// This is a no-op when no key exists for the reference.
        ///
        /// - Parameter keyRef: The ``CryptoKeyReference`` identifying the item to delete.
        /// - Throws: ``KeychainError/platformUnsupported(_:)`` if the crypto backend is unavailable,
        ///   or another ``KeychainError`` on failure.
        ///
        /// ```swift
        /// try await Keychain.shared.deleteCryptoKey(keyRef: keyRef)
        /// ```
        public func deleteCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws {
            try engine.deleteCryptoKey(keyRef: keyRef)
        }
    }

    extension KeychainEngine {
        package func saveCryptoKey(_ key: StoredSecKey, for keyRef: CryptoKeyReference<StoredSecKey>) throws {
            SwiftyChainLoggers.keychain.debug(
                "saveCryptoKey started for tag=\(keyRef.tag, privacy: .private(mask: .hash))"
            )
            do {
                try cryptoBackend().addCryptoKey(
                    key.rawValue,
                    query: cryptoKeyQuery(for: keyRef),
                    attributes: CryptoKeyAttributes(accessibility: keyRef.accessibility)
                )
            } catch {
                SwiftyChainLoggers.keychain.debug(
                    "saveCryptoKey failed for tag=\(keyRef.tag, privacy: .private(mask: .hash)) error=\((error as? KeychainError)?.logName ?? "unknown", privacy: .public)"
                )
                throw error
            }
            SwiftyChainLoggers.keychain.debug(
                "saveCryptoKey succeeded for tag=\(keyRef.tag, privacy: .private(mask: .hash))"
            )
        }

        package func loadCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws -> StoredSecKey {
            StoredSecKey(try cryptoBackend().loadCryptoKey(query: cryptoKeyQuery(for: keyRef)))
        }

        package func deleteCryptoKey(keyRef: CryptoKeyReference<StoredSecKey>) throws {
            try cryptoBackend().deleteCryptoKey(query: cryptoKeyQuery(for: keyRef))
        }

        package func cryptoBackend() throws -> any KeychainCryptoBackend {
            guard backend.capabilities.contains(.cryptoKeys), let cryptoBackend = backend as? any KeychainCryptoBackend
            else {
                SwiftyChainLoggers.keychain.debug("Crypto key operation requested on a backend without cryptoKeys")
                throw KeychainError.platformUnsupported("Cryptographic keys are not supported by this keychain backend")
            }
            return cryptoBackend
        }

        private func cryptoKeyQuery(for keyRef: CryptoKeyReference<StoredSecKey>) -> CryptoKeyQuery {
            CryptoKeyQuery(tag: keyRef.tag, accessGroup: keyRef.accessGroup)
        }
    }
#endif
