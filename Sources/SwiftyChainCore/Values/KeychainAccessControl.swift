/// Authentication required before a protected item can be read or used.
///
/// Apple platforms use the system prompt. Linux, tvOS, and the macOS legacy store
/// reject these policies. In-memory backends store the policy without prompting.
public enum KeychainAccessControl: Sendable, Hashable, CaseIterable {
    /// Biometry or the device passcode.
    case userPresence
    /// Any enrolled biometric identity.
    case biometryAny
    /// Only the currently enrolled biometric identities.
    case biometryCurrentSet
    /// The device passcode.
    case devicePasscode
}
