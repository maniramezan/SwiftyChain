#if canImport(Dispatch)
    import Dispatch

    /// The serial executor a ``Keychain`` actor uses when Dispatch is available.
    ///
    /// Security and libsecret calls block their thread while the platform keychain
    /// responds. A dedicated serial dispatch queue keeps these calls off Swift's
    /// cooperative pool. Each ``Keychain`` has its own queue, so a call waiting on a
    /// biometric prompt, or a slow custom backend, only holds up its own instance.
    ///
    /// On Linux, the Secret Service backend also serializes every libsecret call in the
    /// process (see `SecretServiceClient`). A hung keyring daemon is found with a
    /// liveness ping within a few seconds, after which calls fail fast with
    /// ``KeychainError/timedOut`` until it answers again.
    package final class KeychainExecutor: SerialExecutor {
        /// Set on every executor's queue, so tests can check where keychain work runs.
        package static let queueKey = DispatchSpecificKey<Bool>()

        private let queue: DispatchQueue

        package init() {
            queue = DispatchQueue(label: "dev.manman.SwiftyChain.Keychain", qos: .userInitiated)
            queue.setSpecific(key: Self.queueKey, value: true)
        }

        /// Whether the caller is running on the executor's queue.
        package static var isCurrent: Bool {
            DispatchQueue.getSpecific(key: queueKey) == true
        }

        package func enqueue(_ job: consuming ExecutorJob) {
            let job = UnownedJob(job)
            let executor = asUnownedSerialExecutor()
            queue.async {
                job.runSynchronously(on: executor)
            }
        }

        package func asUnownedSerialExecutor() -> UnownedSerialExecutor {
            UnownedSerialExecutor(ordinary: self)
        }
    }
#endif
