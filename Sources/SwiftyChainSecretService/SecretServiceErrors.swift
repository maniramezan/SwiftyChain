import SwiftyChainCore

/// A GLib error reduced to its domain and code. The GLib message is deliberately not
/// kept: it can contain item details, and SwiftyChain never surfaces backend diagnostics.
package struct SecretServiceFailure: Sendable, Hashable {
    package let domain: String
    package let code: Int32

    package init(domain: String, code: Int32) {
        self.domain = domain
        self.code = code
    }
}

/// Why the Secret Service can't be used at all on this machine.
package enum SecretServiceUnavailability: Sendable, Hashable {
    case libraryMissing
    case libraryTooOld
    case dynamicLoadingUnavailable
    case noSessionBus
    case noProvider
    case noDefaultCollection

    package var error: KeychainError {
        switch self {
        case .libraryMissing:
            .platformUnsupported(
                "libsecret is not installed. Install libsecret-1-0 (or your distribution's equivalent) to use the Secret Service"
            )
        case .libraryTooOld:
            .platformUnsupported("The installed libsecret is too old. SwiftyChain needs libsecret 0.19 or newer")
        case .dynamicLoadingUnavailable:
            .platformUnsupported(
                "This binary is statically linked and can't load libsecret. Build without the static Linux SDK to use the Secret Service"
            )
        case .noSessionBus:
            .platformUnsupported("No D-Bus session bus is available, so the Secret Service can't be reached")
        case .noProvider:
            .platformUnsupported("No Secret Service provider, such as GNOME Keyring or KWallet, is running")
        case .noDefaultCollection:
            .platformUnsupported(
                "The Secret Service provider has no default collection to store items in. Create or expose one in the provider"
            )
        }
    }
}

/// Maps libsecret and GLib failures to ``KeychainError``.
package enum SecretServiceErrors {
    private static let secretDomain = "secret-error"
    private static let ioDomain = "g-io-error-quark"
    private static let dbusDomain = "g-dbus-error-quark"

    private static let secretIsLocked: Int32 = 2
    private static let secretNoSuchObject: Int32 = 3
    private static let secretAlreadyExists: Int32 = 4
    private static let ioCancelled: Int32 = 19
    private static let ioTimedOut: Int32 = 24
    private static let dbusServiceUnknown: Int32 = 2
    private static let dbusNameHasNoOwner: Int32 = 3
    private static let dbusNoReply: Int32 = 4
    private static let dbusAccessDenied: Int32 = 9
    private static let dbusNoServer: Int32 = 11
    private static let dbusTimeout: Int32 = 12
    private static let dbusDisconnected: Int32 = 15
    private static let dbusTimedOut: Int32 = 20
    private static let dbusSpawnErrors: ClosedRange<Int32> = 23...34

    /// Whether libsecret reported that an object, such as a collection, doesn't exist.
    package static func isNoSuchObject(_ failure: SecretServiceFailure) -> Bool {
        failure.domain == secretDomain && failure.code == secretNoSuchObject
    }

    /// Whether, after this error, libsecret's cached Secret Service proxy and session
    /// should be dropped so the next call reconnects.
    ///
    /// A restarted keyring daemon forgets the session libsecret opened, and a restarted
    /// bus closes the connection, so every later call through the cached proxy fails.
    /// Outcomes that come from the keyring's contents or the user, such as a missing
    /// item or a dismissed prompt, leave the connection healthy.
    package static func shouldResetConnection(after error: KeychainError) -> Bool {
        switch error {
        case .itemNotFound, .duplicateItem, .userPresenceRequired, .authenticationFailed:
            false
        default:
            true
        }
    }

    /// Whether the failure means the request never reached a live Secret Service, as
    /// when libsecret's cached proxy still addresses a keyring daemon that has since
    /// restarted. Such a call can be retried safely once the connection is reset.
    package static func isStaleConnection(_ failure: SecretServiceFailure) -> Bool {
        guard failure.domain == dbusDomain else { return false }
        return [dbusServiceUnknown, dbusNameHasNoOwner, dbusDisconnected].contains(failure.code)
    }

    /// The error for a failed connection to the D-Bus session bus.
    ///
    /// A bus that is slow or hung is transient, so it reports ``KeychainError/timedOut``;
    /// only a bus that can't be reached at all means the Secret Service is unavailable.
    ///
    /// - Parameters:
    ///   - failure: the GLib error, when there was one.
    ///   - timerFired: whether SwiftyChain's own timeout cancelled the connection attempt.
    package static func sessionBusError(for failure: SecretServiceFailure?, timerFired: Bool) -> KeychainError {
        if timerFired {
            return .timedOut
        }
        if let failure, keychainError(for: failure, timerFired: false) == .timedOut {
            return .timedOut
        }
        return SecretServiceUnavailability.noSessionBus.error
    }

    /// - Parameter timerFired: whether SwiftyChain's own timeout cancelled the call.
    package static func keychainError(for failure: SecretServiceFailure, timerFired: Bool) -> KeychainError {
        if timerFired {
            return .timedOut
        }
        switch (failure.domain, failure.code) {
        case (secretDomain, secretIsLocked):
            return .userPresenceRequired
        case (secretDomain, secretNoSuchObject):
            return .itemNotFound
        case (secretDomain, secretAlreadyExists):
            return .duplicateItem
        case (ioDomain, ioCancelled), (dbusDomain, dbusAccessDenied):
            return .authenticationFailed
        case (ioDomain, ioTimedOut), (dbusDomain, dbusNoReply), (dbusDomain, dbusTimeout), (dbusDomain, dbusTimedOut):
            return .timedOut
        case (dbusDomain, dbusServiceUnknown), (dbusDomain, dbusNameHasNoOwner), (dbusDomain, dbusNoServer),
            (dbusDomain, dbusDisconnected):
            return SecretServiceUnavailability.noProvider.error
        case (dbusDomain, let code) where dbusSpawnErrors.contains(code):
            return SecretServiceUnavailability.noProvider.error
        default:
            return .operationFailed(failure.code)
        }
    }
}
