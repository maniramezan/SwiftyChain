import Security

/// Keychain accessibility policy backed by `kSecAttrAccessible*` constants.
public enum KeychainAccessibility: Sendable, Hashable {
    case afterFirstUnlock
    case afterFirstUnlockThisDeviceOnly
    case whenUnlocked
    case whenUnlockedThisDeviceOnly
    case whenPasscodeSetThisDeviceOnly

    var secValue: CFString {
        switch self {
        case .afterFirstUnlock:
            kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly:
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlocked:
            kSecAttrAccessibleWhenUnlocked
        case .whenUnlockedThisDeviceOnly:
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly:
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}
