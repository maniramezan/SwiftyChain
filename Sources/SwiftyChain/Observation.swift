#if Observation
    /// An event emitted when a keychain item changes.
    ///
    /// Received via ``Keychain/observeKeychainChanges(service:accessGroup:)``.
    ///
    /// ```swift
    /// import OSLog
    ///
    /// let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")
    ///
    /// for await event in await Keychain.shared.observeKeychainChanges(service: "com.example.app") {
    ///     logger.debug("Observed change: \(String(describing: event.kind), privacy: .public)")
    /// }
    /// ```
    public struct KeychainChangeEvent: Sendable, Hashable {
        /// The service identifier associated with the changed item.
        public let service: String
        /// The account identifier of the changed item, or `nil` for bulk operations.
        public let account: String?
        /// The kind of change that occurred.
        public let kind: Kind

        /// The type of mutation that triggered a ``KeychainChangeEvent``.
        public enum Kind: Sendable, Hashable {
            /// A new item was saved.
            case saved
            /// An existing item was updated.
            case updated
            /// A specific item was deleted.
            case deleted
            /// All items for the service were deleted in bulk.
            case bulkDeleted
        }

        /// Creates a keychain change event.
        ///
        /// - Parameters:
        ///   - service: The service identifier.
        ///   - account: The account identifier, or `nil` for bulk operations.
        ///   - kind: The kind of change.
        public init(service: String, account: String? = nil, kind: Kind) {
            self.service = service
            self.account = account
            self.kind = kind
        }
    }
#endif
