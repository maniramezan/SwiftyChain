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
    /// The platform keychain returned data in an unexpected format.
    case unexpectedData
    /// Serialization of the value into `Data` failed. Contains a description of the underlying error.
    case encodingFailed(String)
    /// Deserialization of `Data` back into the value type failed. Contains a description of the underlying error.
    case decodingFailed(String)
    /// The platform keychain reported a failure with this status code.
    ///
    /// On Apple platforms the code is the Security framework `OSStatus`. On Linux
    /// it is the libsecret or GLib error code.
    case operationFailed(Int32)
    /// The app lacks entitlements to access the specified access group (Apple platforms).
    case accessGroupDenied
    /// The requested operation is not available on this platform or configuration.
    ///
    /// The message names the reason, such as an option the platform can't honor or,
    /// on Linux, a missing libsecret, D-Bus session, or Secret Service provider.
    case platformUnsupported(String)
    /// The platform keychain did not respond before the operation's timeout elapsed.
    case timedOut
}

extension KeychainError {
    package static func encodingFailed(_ error: any Error) -> KeychainError {
        .encodingFailed(String(describing: error))
    }

    package static func decodingFailed(_ error: any Error) -> KeychainError {
        .decodingFailed(String(describing: error))
    }

    /// Whether the error is an outcome the caller receives and handles, such as a missing
    /// item, rather than a fault in the platform keychain. Expected outcomes are logged at
    /// debug level; only faults are logged as errors.
    package var isExpectedOutcome: Bool {
        switch self {
        case .unexpectedData, .operationFailed:
            false
        default:
            true
        }
    }

    package var logName: String {
        switch self {
        case .itemNotFound:
            "itemNotFound"
        case .duplicateItem:
            "duplicateItem"
        case .authenticationFailed:
            "authenticationFailed"
        case .userPresenceRequired:
            "userPresenceRequired"
        case .unexpectedData:
            "unexpectedData"
        case .encodingFailed:
            "encodingFailed"
        case .decodingFailed:
            "decodingFailed"
        case .operationFailed:
            "operationFailed"
        case .accessGroupDenied:
            "accessGroupDenied"
        case .platformUnsupported:
            "platformUnsupported"
        case .timedOut:
            "timedOut"
        }
    }
}
