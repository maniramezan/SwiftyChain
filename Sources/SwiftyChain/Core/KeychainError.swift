import Foundation

/// Errors surfaced by SwiftyChain operations.
public enum KeychainError: Error, Sendable, Equatable {
    /// No keychain item matched the query.
    case itemNotFound
    /// An item already exists for the given key. Use ``Keychain/upsert(_:for:)`` to overwrite.
    case duplicateItem
    /// The user declined biometric or password authentication.
    case authenticationFailed
    /// The item requires user presence (e.g., biometrics) but none was requested.
    case userPresenceRequired
    /// The Security framework returned data in an unexpected format.
    case unexpectedData
    /// Serialization of the value into `Data` failed. Contains a description of the underlying error.
    case encodingFailed(String)
    /// Deserialization of `Data` back into the value type failed. Contains a description of the underlying error.
    case decodingFailed(String)
    /// The Security framework returned a non-zero `OSStatus` code.
    case operationFailed(OSStatus)
    /// The app lacks entitlements to access the specified access group.
    case accessGroupDenied
    /// The requested operation is not available on this platform or configuration.
    case platformUnsupported(String)
}

extension KeychainError {
    static func encodingFailed(_ error: any Error) -> KeychainError {
        .encodingFailed(String(describing: error))
    }

    static func decodingFailed(_ error: any Error) -> KeychainError {
        .decodingFailed(String(describing: error))
    }
}
