#if os(Linux)
    import Foundation
    import SwiftyChain
    import SwiftyChainSecretService
    import Testing

    /// Linux-specific behavior checked against a real Secret Service provider.
    @Suite(
        "Secret Service integration",
        .serialized,
        .enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_SECRET_SERVICE_INTEGRATION"] == "1")
    )
    struct SecretServiceIntegrationTests {
        private static func uniqueService() -> String {
            "dev.manman.SwiftyChain.integration.\(UUID().uuidString)"
        }

        @Test
        func keysContainingNULAreRejectedBeforeReachingLibsecret() async throws {
            let keychain = Keychain(backend: SecretServiceBackend())
            let prefix = Self.uniqueService()
            let alpha = KeychainKey<String>(service: "\(prefix)\0alpha", account: "token")
            let beta = KeychainKey<String>(service: "\(prefix)\0beta", account: "token")
            let labelled = KeychainKey<String>(service: prefix, account: "token", label: "bad\0label")
            let attributeError = KeychainError.platformUnsupported(
                "Secret Service attributes cannot contain NUL characters"
            )

            await #expect(throws: attributeError) { try await keychain.save("alpha-secret", for: alpha) }
            await #expect(throws: attributeError) { try await keychain.load(key: beta) }
            await #expect(throws: attributeError) { try await keychain.delete(key: beta) }
            await #expect(
                throws: KeychainError.platformUnsupported("Secret Service labels cannot contain NUL characters")
            ) {
                try await keychain.save("value", for: labelled)
            }
            #expect(try await keychain.allAccounts(service: prefix).isEmpty)
        }

        @Test
        func unscopedBulkDeletesAreRejected() async throws {
            let keychain = Keychain(backend: SecretServiceBackend())
            let service = Self.uniqueService()
            let kept = KeychainKey<String>(service: service, account: "kept")
            try await keychain.save("kept", for: kept)
            defer { Self.cleanUp(service: service) }
            let unscoped = KeychainError.platformUnsupported(
                "Deleting without a service, server, or access group is not supported by this keychain backend"
            )

            await #expect(throws: unscoped) {
                try await keychain.deleteAllItems(matching: KeychainDeleteQuery())
            }
            await #expect(throws: unscoped) {
                try await keychain.deleteAllItems(matching: KeychainDeleteQuery(itemClass: .internetPassword))
            }
            await #expect(throws: unscoped) {
                try await keychain.deleteAllItems(matching: KeychainDeleteQuery(service: ""))
            }

            #expect(try await keychain.load(key: kept) == "kept")
        }

        @Test
        func anItemWithAnEmptyServiceCanBeDeleted() async throws {
            let keychain = Keychain(backend: SecretServiceBackend())
            let key = KeychainKey<String>(service: "", account: "\(Self.uniqueService()).account")
            try await keychain.save("value", for: key)

            try await keychain.delete(key: key)

            #expect(try await keychain.loadIfPresent(key: key) == nil)
        }

        @Test
        func deletingAnItemThatIsAlreadyGoneSucceeds() async throws {
            let keychain = Keychain(backend: SecretServiceBackend())
            let key = KeychainKey<String>(service: Self.uniqueService(), account: "token")

            try await keychain.delete(key: key)
        }

        @Test
        func updatesChangeTheItemInPlace() async throws {
            let service = Self.uniqueService()
            let key = KeychainKey<String>(service: service, account: "token")
            let keychain = Keychain(backend: SecretServiceBackend())
            defer { Self.cleanUp(service: service) }
            try await keychain.save("first", for: key)

            try await keychain.update("second", for: key)
            try await keychain.upsert("third", for: key)

            let matches = try SecretServiceClient(timeout: .seconds(30)).search(
                SecretServiceAttributes.matching(KeychainQuery(itemClass: .genericPassword, service: service)),
                loadSecrets: true
            )
            #expect(matches.count == 1)
            #expect(matches.first?.secret == Data("third".utf8))
            #expect(try await keychain.load(key: key) == "third")
        }

        @Test
        func concurrentSavesFromSeparateInstancesDetectDuplicates() async throws {
            let service = Self.uniqueService()
            let key = KeychainKey<String>(service: service, account: "token")
            defer { Self.cleanUp(service: service) }

            let outcomes = await withTaskGroup(of: KeychainError?.self) { group in
                for index in 0..<8 {
                    group.addTask {
                        let keychain = Keychain(backend: SecretServiceBackend())
                        do {
                            try await keychain.save("value-\(index)", for: key)
                            return nil
                        } catch let error as KeychainError {
                            return error
                        } catch {
                            return .operationFailed(-1)
                        }
                    }
                }
                var outcomes: [KeychainError?] = []
                for await outcome in group {
                    outcomes.append(outcome)
                }
                return outcomes
            }

            #expect(outcomes.filter { $0 == nil }.count == 1)
            #expect(outcomes.filter { $0 == .duplicateItem }.count == 7)
            #expect(try await Keychain(backend: SecretServiceBackend()).allAccounts(service: service) == ["token"])
        }

        private static func cleanUp(service: String) {
            do {
                try SecretServiceBackend().delete(
                    matching: KeychainQuery(itemClass: .genericPassword, service: service)
                )
            } catch {
                Issue.record("Could not clean up integration test items: \(error)")
            }
        }
    }

    @Suite("Keychain executor on Linux")
    struct KeychainExecutorTests {
        @Test
        func keychainWorkRunsOffTheCooperativePool() async throws {
            let probe = ExecutorProbeBackend()
            let keychain = Keychain(backend: probe)
            let key = KeychainKey<String>(service: "tests.executor", account: "a")

            try await keychain.save("value", for: key)
            _ = try await keychain.loadIfPresent(key: key)
            try await keychain.delete(key: key)

            #expect(probe.ranOnKeychainExecutor)
            #expect(!KeychainExecutor.isCurrent)
        }
    }

    /// Records whether backend calls arrive on ``KeychainExecutor``'s queue.
    private final class ExecutorProbeBackend: KeychainBackend, @unchecked Sendable {
        let capabilities: KeychainBackendCapabilities = []
        private let lock = NSLock()
        private var observed = true

        var ranOnKeychainExecutor: Bool {
            lock.withLock { observed }
        }

        func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {
            record()
        }

        func data(matching query: KeychainQuery) throws -> Data {
            record()
            throw KeychainError.itemNotFound
        }

        func contains(matching query: KeychainQuery) throws -> Bool {
            record()
            return false
        }

        func accounts(matching query: KeychainQuery) throws -> [String] {
            record()
            return []
        }

        func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
            record()
        }

        func delete(matching query: KeychainQuery) throws {
            record()
        }

        private func record() {
            let isCurrent = KeychainExecutor.isCurrent
            lock.withLock { observed = observed && isCurrent }
        }
    }
#endif
