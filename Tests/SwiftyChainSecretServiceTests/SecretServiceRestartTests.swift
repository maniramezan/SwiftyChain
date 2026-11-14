#if os(Linux)
    import Foundation
    import SwiftyChainCore
    import SwiftyChainSecretService
    import Testing

    /// Runs only inside `scripts/with-gnome-keyring.sh` with
    /// `SWIFTYCHAIN_SECRET_SERVICE_RESTART=1`. It restarts the keyring daemon, so it must
    /// not run alongside other Secret Service tests.
    @Suite(
        "Secret Service daemon restart",
        .enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_SECRET_SERVICE_RESTART"] == "1")
    )
    struct SecretServiceRestartTests {
        @Test
        func recoversAfterTheKeyringDaemonRestarts() throws {
            let backend = SecretServiceBackend(timeout: .seconds(10))
            let service = "tests.restart.\(UUID().uuidString)"
            let key = KeychainQuery(itemClass: .genericPassword, service: service, account: "a")
            try backend.add(key, attributes: KeychainAttributes(data: Data("before".utf8)))
            defer {
                do {
                    try backend.delete(matching: KeychainQuery(itemClass: .genericPassword, service: service))
                } catch {
                    Issue.record("Could not clean up restart test items: \(error)")
                }
            }

            try Self.restartKeyringDaemon()

            #expect(try backend.data(matching: key) == Data("before".utf8))
            try backend.update(matching: key, to: KeychainAttributes(data: Data("after".utf8)))
            #expect(try backend.data(matching: key) == Data("after".utf8))
        }

        private static func restartKeyringDaemon() throws {
            let script = try #require(ProcessInfo.processInfo.environment["SWIFTYCHAIN_KEYRING_SCRIPT"])
            try #require(try runCommand([script, "--restart-keyring"]) == 0)
        }
    }
#endif
