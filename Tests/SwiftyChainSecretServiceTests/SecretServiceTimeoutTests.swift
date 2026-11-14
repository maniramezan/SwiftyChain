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
                    data: Data("value".utf8)
                )
            }
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
