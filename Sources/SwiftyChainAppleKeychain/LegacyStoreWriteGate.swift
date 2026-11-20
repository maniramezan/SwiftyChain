#if os(macOS)
    import Foundation

    /// Orders this process's writes to the macOS legacy keychain.
    ///
    /// `SecItemAdd` stores a key in the legacy keychain in two steps: it imports the key,
    /// then looks the import up again to set its attributes. A password write that another
    /// thread of the same process commits between the two makes the lookup miss, and the
    /// add fails with `errSecItemNotFound`. Writes from other processes don't cause this.
    ///
    /// A key add therefore takes the gate exclusively, and every other legacy write shares
    /// it: password writes still run alongside each other, but none overlaps a key add.
    /// Reads don't take the gate.
    package final class LegacyStoreWriteGate: @unchecked Sendable {
        package static let shared = LegacyStoreWriteGate()

        // A pthread lock must keep its address, so it lives on the heap.
        private let lock: UnsafeMutablePointer<pthread_rwlock_t>

        private init() {
            lock = .allocate(capacity: 1)
            lock.initialize(to: pthread_rwlock_t())
            pthread_rwlock_init(lock, nil)
        }

        deinit {
            pthread_rwlock_destroy(lock)
            lock.deinitialize(count: 1)
            lock.deallocate()
        }

        /// Runs a write that other writes may overlap, except a key add.
        package func shared<T>(_ body: () throws -> T) rethrows -> T {
            pthread_rwlock_rdlock(lock)
            defer { pthread_rwlock_unlock(lock) }
            return try body()
        }

        /// Runs a key add, which no other legacy write may overlap.
        package func exclusive<T>(_ body: () throws -> T) rethrows -> T {
            pthread_rwlock_wrlock(lock)
            defer { pthread_rwlock_unlock(lock) }
            return try body()
        }
    }
#endif
