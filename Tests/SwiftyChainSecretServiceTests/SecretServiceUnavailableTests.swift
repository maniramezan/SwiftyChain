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
#endif
