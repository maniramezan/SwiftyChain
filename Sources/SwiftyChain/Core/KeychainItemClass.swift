/// Supported keychain item classes, corresponding to `kSecClass` constants.
///
/// You typically don't use this type directly: ``KeychainKey`` always targets
/// ``genericPassword``, ``InternetPasswordKey`` always targets ``internetPassword``,
/// and ``CryptoKeyReference`` always targets ``cryptographicKey``.
/// ``KeychainDeleteQuery`` accepts this value for custom bulk-delete operations.
public enum KeychainItemClass: Sendable, Hashable {
    /// A generic password item (`kSecClassGenericPassword`).
    case genericPassword
    /// An internet password item (`kSecClassInternetPassword`).
    ///
    /// Includes server, port, path, protocol, and authentication-type attributes.
    case internetPassword
    #if Cryptography
        /// A cryptographic key item (`kSecClassKey`).
        case cryptographicKey
    #endif
}
