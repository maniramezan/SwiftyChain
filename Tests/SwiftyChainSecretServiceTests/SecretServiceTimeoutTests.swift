#if os(Linux)
    import Foundation
    import Synchronization
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
                    attributes: KeychainAttributes(data: Data("value".utf8))
                )
            }
            #expect(ContinuousClock.now - started < .seconds(10))
        }

        /// A liveness ping finds the hung provider long before the 60-second timeout, and
        /// the next call fails after a single ping instead of probing again.
        @Test
        func hungProviderIsDetectedLongBeforeTheTimeout() {
            let backend = SecretServiceBackend(timeout: .seconds(60), livenessInterval: .seconds(1))
            let query = KeychainQuery(itemClass: .genericPassword, service: "tests.timeout.liveness", account: "a")

            let first = ContinuousClock.now
            #expect(throws: KeychainError.timedOut) {
                _ = try backend.data(matching: query)
            }
            #expect(ContinuousClock.now - first < .seconds(10))

            let second = ContinuousClock.now
            #expect(throws: KeychainError.timedOut) {
                _ = try backend.data(matching: query)
            }
            #expect(ContinuousClock.now - second < .seconds(3))
        }

        /// Calls queued behind a hung call ping the provider while they wait, so they
        /// fail within seconds even with a 60-second timeout.
        @Test
        func callsQueuedBehindAHungCallFailLongBeforeTheTimeout() {
            let callers = 5
            let outcomes = Mutex<[KeychainError?]>([])
            let finished = DispatchGroup()
            let started = ContinuousClock.now

            for index in 0..<callers {
                finished.enter()
                Thread {
                    let backend = SecretServiceBackend(timeout: .seconds(60), livenessInterval: .seconds(1))
                    let query = KeychainQuery(
                        itemClass: .genericPassword,
                        service: "tests.timeout.liveness.queued",
                        account: "a\(index)"
                    )
                    var outcome: KeychainError?
                    do {
                        _ = try backend.data(matching: query)
                    } catch let error as KeychainError {
                        outcome = error
                    } catch {
                        outcome = .operationFailed(-1)
                    }
                    outcomes.withLock { $0.append(outcome) }
                    finished.leave()
                }.start()
            }
            finished.wait()

            let results = outcomes.withLock { $0 }
            #expect(results.count == callers)
            #expect(results.allSatisfy { $0 == .timedOut })
            #expect(ContinuousClock.now - started < .seconds(10))
        }

        /// Calls waiting behind a hung call share its deadline instead of each waiting a
        /// full timeout in turn, which would take `callers × timeout`.
        @Test
        func queuedCallsTimeOutTogether() {
            let callers = 5
            let outcomes = Mutex<[KeychainError?]>([])
            let finished = DispatchGroup()
            let started = ContinuousClock.now

            // Each caller gets its own thread, so the cooperative pool's width can't
            // serialize the calls.
            for index in 0..<callers {
                finished.enter()
                Thread {
                    let backend = SecretServiceBackend(timeout: .seconds(2))
                    let query = KeychainQuery(
                        itemClass: .genericPassword,
                        service: "tests.timeout.queued",
                        account: "a\(index)"
                    )
                    var outcome: KeychainError?
                    do {
                        _ = try backend.data(matching: query)
                    } catch let error as KeychainError {
                        outcome = error
                    } catch {
                        outcome = .operationFailed(-1)
                    }
                    outcomes.withLock { $0.append(outcome) }
                    finished.leave()
                }.start()
            }
            finished.wait()

            let results = outcomes.withLock { $0 }
            #expect(results.count == callers)
            #expect(results.allSatisfy { $0 == .timedOut })
            #expect(ContinuousClock.now - started < .seconds(6))
        }
    }
#endif
