/// The kind of backend call a query is validated for.
package enum KeychainOperation: Sendable, Hashable {
    case add
    case read
    case update
    case delete
}

/// Rejects queries that use options a backend does not support.
///
/// This is the only place that turns an unsupported option into
/// ``KeychainError/platformUnsupported(_:)``, so every backend reports it the same way.
/// Backend-specific limits on attribute values, such as the Secret Service rejecting
/// NUL characters, stay in the backend.
package enum KeychainQueryValidator {
    package static func validate(
        _ query: KeychainQuery,
        attributes: KeychainAttributes? = nil,
        for operation: KeychainOperation,
        against capabilities: KeychainBackendCapabilities
    ) throws {
        if attributes?.accessControl != nil, !capabilities.contains(.accessControl) {
            try reject(
                "accessControl", message: "Access control is not supported by this keychain backend or configuration")
        }
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
        if operation == .delete, !capabilities.contains(.unscopedBulkDelete), !isScoped(query) {
            try reject(
                "unscopedBulkDelete",
                message: "Deleting without a service, server, or access group is not supported by this keychain backend"
            )
        }
    }

    /// Whether a delete is limited to items the caller owns.
    ///
    /// It must name a non-empty service (or server, for internet passwords) or access
    /// group, or one exact item: a service or server together with an account. Only the
    /// item class's own primary attribute counts, so a generic-password query that names
    /// only a server is unscoped.
    package static func isScoped(_ query: KeychainQuery) -> Bool {
        let primary: String? =
            switch query.itemClass.kind {
            case .genericPassword: query.service
            case .internetPassword: query.server
            case .cryptographicKey: nil
            }
        if let primary, !primary.isEmpty {
            return true
        }
        if let accessGroup = query.accessGroup, !accessGroup.isEmpty {
            return true
        }
        return primary != nil && query.account != nil
    }

    private static func reject(_ capability: String, message: String) throws {
        SwiftyChainLoggers.backend.debug(
            "Rejected query using unsupported capability=\(capability, privacy: .public)"
        )
        throw KeychainError.platformUnsupported(message)
    }
}
