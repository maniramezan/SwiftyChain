#if Observation
    import Foundation
    import Synchronization

    /// Thread-safe registry of change observers shared by every copy of a ``KeychainEngine``.
    package final class KeychainObserverRegistry: Sendable {
        package static let platformDefault = KeychainObserverRegistry()

        private struct Observer: Sendable {
            let service: String?
            let server: String?
            let accessGroup: String?
            let continuation: AsyncStream<KeychainChangeEvent>.Continuation
        }

        private let observers = Mutex<[UUID: Observer]>([:])

        package init() {}

        package func register(service: String? = nil, server: String? = nil, accessGroup: String?) -> AsyncStream<
            KeychainChangeEvent
        > {
            let id = UUID()
            return AsyncStream { continuation in
                observers.withLock {
                    $0[id] = Observer(
                        service: service, server: server, accessGroup: accessGroup, continuation: continuation)
                }
                SwiftyChainLoggers.observation.debug(
                    "Registered observer for service=\(service ?? server ?? "<all>", privacy: .private(mask: .hash))"
                )
                continuation.onTermination = { [weak self] _ in
                    self?.remove(id: id)
                }
            }
        }

        package func emit(_ event: KeychainChangeEvent, accessGroup: String?) {
            let matching = observers.withLock { observers in
                observers.values.filter { observer in
                    observer.service == event.service && observer.server == event.server
                        && (observer.accessGroup == nil || observer.accessGroup == accessGroup)
                }
            }
            SwiftyChainLoggers.observation.debug(
                "Emitting observation event=\(String(describing: event.kind), privacy: .public) service=\(event.service ?? event.server ?? "<all>", privacy: .private(mask: .hash)) account=\(event.account ?? "<all>", privacy: .private(mask: .hash)) observers=\(matching.count, privacy: .public)"
            )
            for observer in matching {
                observer.continuation.yield(event)
            }
        }

        private func remove(id: UUID) {
            observers.withLock { _ = $0.removeValue(forKey: id) }
            SwiftyChainLoggers.observation.debug("Removed observer")
        }
    }
#endif
