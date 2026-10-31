#if os(Linux)
    import Foundation
    import SwiftyChainCore
    import SwiftyChainSecretService
    import Testing

    /// Runs only when CI has frozen the keyring daemon (for example with `pkill -STOP`)
    /// and set `SWIFTYCHAIN_SECRET_SERVICE_HUNG=1`.
    @Suite(
        "Secret Service timeout",
        .enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_SECRET_SERVICE_HUNG"] == "1")
    )
    struct SecretServiceTimeoutTests {
        @Test
        func hungDaemonTimesOut() throws {
            let backend = SecretServiceBackend(timeout: .seconds(2))
            let started = ContinuousClock.now

            #expect(throws: KeychainError.timedOut) {
                try backend.add(
                    KeychainQuery(itemClass: .genericPassword, service: "tests.timeout", account: "a"),
                    data: Data("value".utf8)
                )
            }
            #expect(ContinuousClock.now - started < .seconds(10))
        }
    }
#endif
