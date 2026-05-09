/// Supported keychain item classes.
public enum KeychainItemClass: Sendable, Hashable {
    case genericPassword
    case internetPassword
    #if Cryptography
        case cryptographicKey
    #endif
}
