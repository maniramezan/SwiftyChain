import Foundation

#if canImport(Security)
    import SwiftyChainAppleKeychain
#elseif os(Linux)
    import SwiftyChainSecretService
#endif

/// Chooses the ``KeychainBackend`` that `Keychain()` and `KeychainStorage` use
/// when the caller doesn't supply one.
package enum PlatformDefaultBackend {
    package static func make(configuration: KeychainConfiguration = .init()) -> any KeychainBackend {
        #if canImport(Security)
            AppleKeychainBackend(configuration: configuration)
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
package struct UnsupportedPlatformBackend: KeychainBackend {
    package let capabilities: KeychainBackendCapabilities = []

    package init() {}

    package func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {
        try unsupported()
    }

    package func data(matching query: KeychainQuery) throws -> Data {
        try unsupported()
    }

    package func contains(matching query: KeychainQuery) throws -> Bool {
        try unsupported()
    }

    package func accounts(matching query: KeychainQuery) throws -> [String] {
        try unsupported()
    }

    package func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        try unsupported()
    }

    package func delete(matching query: KeychainQuery) throws {
        try unsupported()
    }

    private func unsupported() throws -> Never {
        SwiftyChainLoggers.backend.debug("Keychain operation requested on a platform without a keychain backend")
        throw KeychainError.platformUnsupported("No secure storage is available on this platform")
    }
}
