/// Selects the platform keychain store used by an engine.
///
/// The choice affects macOS only. It does not migrate items between stores.
public struct KeychainConfiguration: Sendable, Hashable {
    /// The macOS keychain implementation to use.
    public enum MacOSStore: Sendable, Hashable {
        /// The legacy login keychain. Accessibility policies are not enforced.
        case legacy
        /// The data-protection keychain. Requires a signed, entitled host.
        case dataProtection
    }

    /// The selected macOS store. Defaults to the legacy login keychain.
    public let macOSStore: MacOSStore

    public init(macOSStore: MacOSStore = .legacy) {
        self.macOSStore = macOSStore
    }
}
