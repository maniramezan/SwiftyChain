#if os(Linux)
    import Dispatch

    /// The serial executor every ``Keychain`` actor runs on under Linux.
    ///
    /// libsecret's calls are synchronous and can block for up to the backend timeout,
    /// for example while an unlock prompt is open or the keyring daemon is hung. Running
    /// them on Swift's cooperative pool, which has one thread per core, would let a
    /// few stuck calls stall every async task in the process. This executor moves that
    /// blocking onto one dedicated dispatch queue instead.
    ///
    /// All ``Keychain`` instances share the queue. The Secret Service backend serializes
    /// its calls process-wide anyway, so separate queues would only add threads that
    /// wait on one another.
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
