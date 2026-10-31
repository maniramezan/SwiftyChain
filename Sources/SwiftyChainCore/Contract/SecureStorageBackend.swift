import Foundation

/// The storage contract every SwiftyChain backend implements.
///
/// The `Keychain` actor talks to platform storage only through this protocol, so
/// the public API behaves the same on Apple platforms, Linux, and in tests.
/// Backends must follow these rules:
///
/// - A `nil` attribute in a query matches any value. `isSynchronizable == nil`
///   matches both synchronizable and local items.
/// - `add` throws ``KeychainError/duplicateItem`` when an item with the same
///   identity already exists.
/// - `copyMatching` throws ``KeychainError/itemNotFound`` when nothing matches,
///   including for `.all` queries.
/// - `update` changes every matching item, and throws ``KeychainError/itemNotFound``
///   when nothing matches.
/// - `delete` removes every matching item and succeeds when nothing matches.
/// - Errors are ``KeychainError`` values. Platform diagnostics are logged, never
///   carried in the error.
///
/// Callers validate queries against ``capabilities`` with
/// ``SecureStorageQueryValidator`` before calling a backend, so a backend never
/// receives an option it declared unsupported.
package protocol SecureStorageBackend: Sendable {
    /// The optional features this backend supports.
    var capabilities: SecureStorageCapabilities { get }

    func add(_ query: KeychainQuery, data: Data) throws
    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult
    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws
    func delete(matching query: KeychainQuery) throws
}

/// Optional features a ``SecureStorageBackend`` supports beyond the core
/// generic-password operations.
package struct SecureStorageCapabilities: OptionSet, Sendable, Hashable {
    package let rawValue: UInt8

    package init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Items can sync across devices (`isSynchronizable: true`).
    package static let synchronizable = SecureStorageCapabilities(rawValue: 1 << 0)
    /// Items can be scoped to an access group.
    package static let accessGroups = SecureStorageCapabilities(rawValue: 1 << 1)
    /// The backend enforces ``KeychainAccessibility``. Without it the policy is ignored.
    package static let accessibility = SecureStorageCapabilities(rawValue: 1 << 2)
    /// The backend stores internet passwords.
    package static let internetPasswords = SecureStorageCapabilities(rawValue: 1 << 3)
    /// The backend stores cryptographic keys.
    package static let cryptoKeys = SecureStorageCapabilities(rawValue: 1 << 4)

    /// Every capability, for backends with full Apple Keychain semantics.
    package static let all: SecureStorageCapabilities = [
        .synchronizable,
        .accessGroups,
        .accessibility,
        .internetPasswords,
        .cryptoKeys,
    ]
}

/// Rejects queries that use options a backend does not support.
///
/// This is the only place that turns an unsupported option into
/// ``KeychainError/platformUnsupported(_:)``, so every backend reports it the same way.
package enum SecureStorageQueryValidator {
    package static func validate(
        _ query: KeychainQuery,
        against capabilities: SecureStorageCapabilities
    ) throws {
        if query.itemClass == .internetPassword, !capabilities.contains(.internetPasswords) {
            try reject("internetPasswords", message: "Internet passwords are not supported by this keychain backend")
        }
        if query.isSynchronizable == true, !capabilities.contains(.synchronizable) {
            try reject("synchronizable", message: "Synchronizable items are not supported by this keychain backend")
        }
        if query.accessGroup != nil, !capabilities.contains(.accessGroups) {
            try reject("accessGroups", message: "Access groups are not supported by this keychain backend")
        }
    }

    private static func reject(_ capability: String, message: String) throws {
        SwiftyChainLoggers.backend.error(
            "Rejected query using unsupported capability=\(capability, privacy: .public)"
        )
        throw KeychainError.platformUnsupported(message)
    }
}
