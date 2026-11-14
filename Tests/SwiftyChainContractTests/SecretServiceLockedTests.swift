#if os(Linux)
    import Foundation
    import SwiftyChain
    import SwiftyChainSecretService
    import Testing

    @Suite(
        "Locked Secret Service",
        .serialized,
        .enabled(
            if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_SECRET_SERVICE_LOCKED_TESTS"] == "1"
                && ProcessInfo.processInfo.environment["SWIFTYCHAIN_KEYRING_SESSION"] == "1"
        )
    )
    struct SecretServiceLockedTests {
        @Test
        func dismissedUnlockDoesNotLookLikeAMissingCredential() async throws {
            let fixture = LockedSecretServiceFixture()
            defer { fixture.cleanUp() }
            try fixture.storeAndLock()
            let keychain = Keychain(backend: fixture.backend)

            await #expect(throws: KeychainError.userPresenceRequired) {
                try await keychain.loadIfPresent(key: fixture.key)
            }

            try fixture.unlock()
            #expect(try await keychain.load(key: fixture.key) == "secret")
        }

        @Test
        func updateLeavesALockedCredentialUnchanged() async throws {
            let fixture = LockedSecretServiceFixture()
            defer { fixture.cleanUp() }
            try fixture.storeAndLock()
            let keychain = Keychain(backend: fixture.backend)

            await #expect(throws: KeychainError.userPresenceRequired) {
                try await keychain.update("changed", for: fixture.key)
            }

            try fixture.unlock()
            #expect(try await keychain.load(key: fixture.key) == "secret")
        }

        @Test(arguments: [false, true])
        func deletionFailsWhenLockedCredentialsRemain(bulk: Bool) async throws {
            let fixture = LockedSecretServiceFixture()
            defer { fixture.cleanUp() }
            try fixture.storeAndLock()
            let keychain = Keychain(backend: fixture.backend)

            await #expect(throws: KeychainError.userPresenceRequired) {
                if bulk {
                    try await keychain.deleteAll(service: fixture.key.service)
                } else {
                    try await keychain.delete(key: fixture.key)
                }
            }

            try fixture.unlock()
            #expect(try await keychain.load(key: fixture.key) == "secret")
            if bulk {
                try await keychain.deleteAll(service: fixture.key.service)
            } else {
                try await keychain.delete(key: fixture.key)
            }
            #expect(try await keychain.loadIfPresent(key: fixture.key) == nil)
        }
    }

#endif
