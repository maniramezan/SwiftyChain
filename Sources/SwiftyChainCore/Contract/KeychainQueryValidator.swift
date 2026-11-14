/// Rejects queries that use options a backend does not support.
///
/// This is the only place that turns an unsupported option into
/// ``KeychainError/platformUnsupported(_:)``, so every backend reports it the same way.
package enum KeychainQueryValidator {
    package static func validate(
        _ query: KeychainQuery,
        against capabilities: KeychainBackendCapabilities
    ) throws {
        if query.itemClass == .internetPassword, !capabilities.contains(.internetPasswords) {
            try reject("internetPasswords", message: "Internet passwords are not supported by this keychain backend")
        }
        if query.itemClass.kind == .cryptographicKey, !capabilities.contains(.cryptoKeys) {
            try reject("cryptoKeys", message: "Cryptographic keys are not supported by this keychain backend")
        }
        if query.isSynchronizable == true, !capabilities.contains(.synchronizable) {
            try reject("synchronizable", message: "Synchronizable items are not supported by this keychain backend")
        }
        if query.accessGroup != nil, !capabilities.contains(.accessGroups) {
            try reject("accessGroups", message: "Access groups are not supported by this keychain backend")
        }
    }

    private static func reject(_ capability: String, message: String) throws {
        SwiftyChainLoggers.backend.debug(
            "Rejected query using unsupported capability=\(capability, privacy: .public)"
        )
        throw KeychainError.platformUnsupported(message)
    }
}
