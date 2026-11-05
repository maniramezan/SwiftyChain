/// Supported keychain item classes, corresponding to `kSecClass` constants.
///
/// You typically don't use this type directly: ``KeychainKey`` always targets
/// ``genericPassword``, ``InternetPasswordKey`` always targets ``internetPassword``,
/// and `CryptoKeyReference` always targets `cryptographicKey`.
/// ``KeychainDeleteQuery`` accepts this value for custom bulk-delete operations.
///
/// `KeychainItemClass` is a struct rather than an enum so that enabling a package
/// trait, or adding a class in a future release, never breaks an exhaustive `switch`
/// in your code. Compare values with `==` instead.
public struct KeychainItemClass: Sendable, Hashable {
    package enum Kind: Sendable, Hashable {
        case genericPassword
        case internetPassword
        case cryptographicKey
    }

    package let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    /// A generic password item (`kSecClassGenericPassword`).
    public static let genericPassword = KeychainItemClass(kind: .genericPassword)

    /// An internet password item (`kSecClassInternetPassword`).
    ///
    /// Includes server, port, path, protocol, and authentication-type attributes.
    public static let internetPassword = KeychainItemClass(kind: .internetPassword)

    #if Cryptography
        /// A cryptographic key item (`kSecClassKey`).
        public static let cryptographicKey = KeychainItemClass(kind: .cryptographicKey)
    #endif
}
