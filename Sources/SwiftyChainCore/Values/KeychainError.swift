import Foundation

/// Errors surfaced by SwiftyChain operations.
public enum KeychainError: Error, Sendable, Equatable {
    /// No keychain item matched the query.
    case itemNotFound
    /// An item already exists for the given key. Use ``Keychain/upsert(_:for:)`` to overwrite.
    case duplicateItem
    /// Authentication was attempted and failed, such as a wrong password, or access to
    /// the item was denied.
    case authenticationFailed
    /// The user dismissed an authentication prompt: biometry or passcode on Apple
    /// platforms, an unlock prompt on Linux.
    case userCanceled
    /// The item can't be read without user interaction that isn't possible now.
    ///
    /// On Apple platforms this is `errSecInteractionNotAllowed`, which usually means the
    /// device is locked and the item's ``KeychainAccessibility`` doesn't allow reading it
    /// yet. On Linux the keyring holding the item is locked and can't be unlocked, for
    /// example because no prompt can be shown.
    case interactionNotAllowed
    /// The platform keychain returned data in an unexpected format.
    case unexpectedData
    /// Serialization of the value into `Data` failed. Contains a description of the underlying error.
    case encodingFailed(String)
    /// Deserialization of `Data` back into the value type failed. Contains a description of the underlying error.
    case decodingFailed(String)
    /// The platform keychain reported a failure SwiftyChain has no specific case for.
    ///
    /// The code is platform-specific. On Apple platforms it is the Security framework
    /// `OSStatus`, such as `-50` (`errSecParam`). On Linux it is the libsecret or GLib
    /// error code from the error's domain, so the same number can mean different things
    /// in different domains; SwiftyChain's logs record the domain. A code of `0` on Linux
    /// means libsecret failed without reporting an error.
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
    /// The request combines options that contradict each other, such as a synchronizable
    /// item with a `ThisDeviceOnly` accessibility. The message names the conflict.
    case invalidArgument(String)
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
        case .userCanceled:
            "userCanceled"
        case .interactionNotAllowed:
            "interactionNotAllowed"
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
        case .invalidArgument:
            "invalidArgument"
        }
    }
}
