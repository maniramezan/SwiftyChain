#if os(Linux)
    import Foundation
    import SwiftyChainCore
    import SwiftyChainSecretService
    import Testing

    /// Runs only on machines CI has prepared without libsecret, marked by
    /// `SWIFTYCHAIN_EXPECT_NO_LIBSECRET=1`.
    @Suite(
        "Secret Service without libsecret",
        .enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_EXPECT_NO_LIBSECRET"] == "1")
    )
    struct SecretServiceUnavailableTests {
        @Test
        func everyOperationFailsClosed() throws {
            let backend = SecretServiceBackend()
            let query = KeychainQuery(itemClass: .genericPassword, service: "tests.unavailable", account: "a")
            let missing = SecretServiceUnavailability.libraryMissing.error

            #expect(throws: missing) { try backend.add(query, data: Data("value".utf8)) }
            #expect(throws: missing) { try backend.copyMatching(query) }
            #expect(throws: missing) { try backend.delete(matching: query) }
        }
    }

    /// Runs only where CI has pointed `DBUS_SESSION_BUS_ADDRESS` at a bus that doesn't
    /// exist, marked by `SWIFTYCHAIN_EXPECT_NO_SESSION_BUS=1`.
    @Suite(
        "Secret Service without a session bus",
        .enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_EXPECT_NO_SESSION_BUS"] == "1")
    )
    struct SecretServiceNoSessionBusTests {
        @Test
        func everyOperationFailsClosed() throws {
            let backend = SecretServiceBackend(timeout: .seconds(5))
            let query = KeychainQuery(itemClass: .genericPassword, service: "tests.no-bus", account: "a")
            let missing = SecretServiceUnavailability.noSessionBus.error

            #expect(throws: missing) { try backend.add(query, data: Data("value".utf8)) }
            #expect(throws: missing) { try backend.copyMatching(query) }
            #expect(throws: missing) { try backend.delete(matching: query) }
        }
    }

    /// Runs only inside a D-Bus session with no Secret Service provider installed or
    /// activatable, marked by `SWIFTYCHAIN_EXPECT_NO_PROVIDER=1`.
    @Suite(
        "Secret Service without a provider",
        .enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_EXPECT_NO_PROVIDER"] == "1")
    )
    struct SecretServiceNoProviderTests {
        @Test
        func everyOperationFailsClosed() throws {
            let backend = SecretServiceBackend(timeout: .seconds(5))
            let query = KeychainQuery(itemClass: .genericPassword, service: "tests.no-provider", account: "a")
            let missing = SecretServiceUnavailability.noProvider.error

            #expect(throws: missing) { try backend.add(query, data: Data("value".utf8)) }
            #expect(throws: missing) { try backend.copyMatching(query) }
            #expect(throws: missing) { try backend.delete(matching: query) }
        }
    }
#endif
