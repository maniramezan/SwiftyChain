import SwiftyChain

/// A platform whose keychain restrictions the in-memory test doubles reproduce.
///
/// Use it to run a test against Linux's restrictions while developing on a Mac:
///
/// ```swift
/// let keychain = InMemoryKeychain(emulating: .linux)
///
/// await #expect(throws: KeychainError.self) {
///     try await keychain.deleteAllItems(matching: KeychainDeleteQuery())
/// }
/// ```
///
/// Emulation covers the options each platform's backend declares in its
/// `KeychainBackendCapabilities`. Value-level limits that a backend enforces itself,
/// such as the Secret Service rejecting NUL characters in attributes, are not emulated.
public enum EmulatedKeychainPlatform: Sendable, Hashable {
    /// Apple's keychain on iOS, iPadOS, Mac Catalyst, visionOS, and watchOS, which
    /// supports every option.
    case apple
    /// The freedesktop Secret Service on Linux: no synchronizable items, no access
    /// control, no cryptographic keys, and no bulk delete without a service, server,
    /// or access group.
    case linux

    /// The capabilities the platform's backend declares.
    public var capabilities: KeychainBackendCapabilities {
        switch self {
        case .apple:
            InMemoryKeychainBackend.defaultCapabilities
        case .linux:
            [.accessGroups, .internetPasswords]
        }
    }
}
