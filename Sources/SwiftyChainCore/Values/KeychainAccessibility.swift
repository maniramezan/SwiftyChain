/// Keychain accessibility policy, matching the `kSecAttrAccessible*` constants on Apple platforms.
///
/// Controls when a keychain item can be read. Choose the most restrictive policy
/// that still meets your app's needs — tighter policies give users stronger security guarantees.
///
/// `ThisDeviceOnly` variants prevent iCloud Keychain sync and block item migration to
/// a new device; they should be paired with `isSynchronizable: false`.
///
/// On Linux the Secret Service has no accessibility policies, so this value is ignored.
public enum KeychainAccessibility: Sendable, Hashable {
    /// Item is accessible after the device has been unlocked at least once since last boot.
    ///
    /// Suitable for background-refresh tasks that run while the screen is locked.
    case afterFirstUnlock
    /// Like ``afterFirstUnlock`` but the item is not migrated to a new device or iCloud.
    case afterFirstUnlockThisDeviceOnly
    /// Item is accessible only while the device is unlocked. The default policy.
    case whenUnlocked
    /// Like ``whenUnlocked`` but the item is not migrated to a new device or iCloud.
    case whenUnlockedThisDeviceOnly
    /// Item is accessible only when the device has a passcode set.
    ///
    /// The item is deleted if the user removes their passcode. Implies device-only storage.
    case whenPasscodeSetThisDeviceOnly
}
