import SwiftyChainCore
import SwiftyChainSecretService
import Testing

@Suite("Secret Service error mapping")
struct SecretServiceErrorsTests {
    private static let noProvider = SecretServiceUnavailability.noProvider.error

    @Test(
        arguments: [
            (SecretServiceFailure(domain: "secret-error", code: 2), KeychainError.userPresenceRequired),
            (SecretServiceFailure(domain: "secret-error", code: 3), .itemNotFound),
            (SecretServiceFailure(domain: "secret-error", code: 4), .duplicateItem),
            (SecretServiceFailure(domain: "g-io-error-quark", code: 19), .authenticationFailed),
            (SecretServiceFailure(domain: "g-io-error-quark", code: 24), .timedOut),
            (SecretServiceFailure(domain: "g-dbus-error-quark", code: 4), .timedOut),
            (SecretServiceFailure(domain: "g-dbus-error-quark", code: 9), .authenticationFailed),
            (SecretServiceFailure(domain: "g-dbus-error-quark", code: 2), noProvider),
            (SecretServiceFailure(domain: "g-dbus-error-quark", code: 3), noProvider),
            (SecretServiceFailure(domain: "g-dbus-error-quark", code: 25), noProvider),
            (SecretServiceFailure(domain: "secret-error", code: 1), .operationFailed(1)),
            (SecretServiceFailure(domain: "g-io-error-quark", code: 0), .operationFailed(0)),
        ]
    )
    func mapsFailures(_ failure: SecretServiceFailure, _ expected: KeychainError) {
        #expect(SecretServiceErrors.keychainError(for: failure, timerFired: false) == expected)
    }

    @Test
    func ourTimeoutWinsOverTheCancellationError() {
        let cancelled = SecretServiceFailure(domain: "g-io-error-quark", code: 19)

        #expect(SecretServiceErrors.keychainError(for: cancelled, timerFired: true) == .timedOut)
    }

    @Test
    func unavailabilityReasonsAreDistinct() {
        let reasons: [SecretServiceUnavailability] = [.libraryMissing, .libraryTooOld, .noSessionBus, .noProvider]

        #expect(Set(reasons.map { String(describing: $0.error) }).count == reasons.count)
    }
}
