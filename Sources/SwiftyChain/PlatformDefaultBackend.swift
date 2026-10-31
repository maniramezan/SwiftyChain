import Foundation

#if canImport(SwiftyChainAppleKeychain)
    import SwiftyChainAppleKeychain
#elseif os(Linux)
    import SwiftyChainSecretService
#endif

/// Chooses the ``SecureStorageBackend`` that `Keychain()` and `KeychainStorage` use
/// when the caller doesn't supply one.
package enum PlatformDefaultBackend {
    package static func make() -> any SecureStorageBackend {
        #if canImport(SwiftyChainAppleKeychain)
            AppleKeychainBackend()
        #elseif os(Linux)
            SecretServiceBackend()
        #else
            UnsupportedPlatformBackend()
        #endif
    }
}

/// The backend for platforms with no keychain implementation. Every operation
/// throws ``KeychainError/platformUnsupported(_:)``, so code compiles everywhere
/// and fails clearly at runtime instead of silently storing secrets insecurely.
package struct UnsupportedPlatformBackend: SecureStorageBackend {
    package let capabilities: SecureStorageCapabilities = []

    package init() {}

    package func add(_ query: KeychainQuery, data: Data) throws {
        try unsupported()
    }

    package func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        try unsupported()
    }

    package func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        try unsupported()
    }

    package func delete(matching query: KeychainQuery) throws {
        try unsupported()
    }

    private func unsupported() throws -> Never {
        SwiftyChainLoggers.backend.error("Keychain operation requested on a platform without a keychain backend")
        throw KeychainError.platformUnsupported("No secure storage is available on this platform")
    }
}
