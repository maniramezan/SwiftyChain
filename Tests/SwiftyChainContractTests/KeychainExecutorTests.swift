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

        @Test(.timeLimit(.minutes(1)))
        func blockedInstanceDoesNotStallOtherInstances() async throws {
            let (entered, enteredContinuation) = AsyncStream<Void>.makeStream()
            let blocking = BlockingBackend(entered: enteredContinuation)
            let blocked = Keychain(backend: blocking)
            let other = Keychain(backend: ExecutorProbeBackend())
            let key = KeychainKey<String>(service: "tests.executor.isolation", account: "a")

            let stuck = Task { try await blocked.exists(key: key) }
            var iterator = entered.makeAsyncIterator()
            await iterator.next()

            try await other.save("value", for: key)
            blocking.release()
            #expect(try await stuck.value == false)
        }
    }

    /// Blocks its first `contains` call until ``release()``, like a call waiting on a
    /// biometric prompt or a hung Secret Service.
    private final class BlockingBackend: KeychainBackend, @unchecked Sendable {
        let capabilities: KeychainBackendCapabilities = []
        private let entered: AsyncStream<Void>.Continuation
        private let gate = DispatchSemaphore(value: 0)

        init(entered: AsyncStream<Void>.Continuation) {
            self.entered = entered
        }

        func release() {
            gate.signal()
        }

        func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {}

        func data(matching query: KeychainQuery) throws -> Data {
            throw KeychainError.itemNotFound
        }

        func contains(matching query: KeychainQuery) throws -> Bool {
            entered.yield()
            gate.wait()
            return false
        }

        func accounts(matching query: KeychainQuery) throws -> [String] { [] }

        func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {}

        func delete(matching query: KeychainQuery) throws {}
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
