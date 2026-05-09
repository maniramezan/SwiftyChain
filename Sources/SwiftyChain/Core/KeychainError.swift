import Foundation

/// Errors surfaced by SwiftyChain operations.
public enum KeychainError: Error, Sendable, Equatable {
    case itemNotFound
    case duplicateItem
    case authenticationFailed
    case userPresenceRequired
    case unexpectedData
    case encodingFailed(String)
    case decodingFailed(String)
    case operationFailed(OSStatus)
    case accessGroupDenied
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
