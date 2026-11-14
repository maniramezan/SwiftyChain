#if canImport(Dispatch)
    import Foundation
    import SwiftyChain
    import Testing
    @Suite("Keychain executor")
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
            #expect(KeychainExecutor.isCurrent == false)
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
