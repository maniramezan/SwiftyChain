#if canImport(Dispatch)
    import Dispatch

    /// The serial executor every ``Keychain`` actor uses when Dispatch is available.
    ///
    /// Security and libsecret calls block their thread while the platform keychain
    /// responds. A dedicated serial dispatch queue keeps these calls off Swift's
    /// cooperative pool. All ``Keychain`` instances share this queue.
    package final class KeychainExecutor: SerialExecutor {
        package static let shared = KeychainExecutor()

        /// Set on the executor's queue, so tests can check where keychain work runs.
        package static let queueKey = DispatchSpecificKey<Bool>()

        private let queue: DispatchQueue

        private init() {
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
