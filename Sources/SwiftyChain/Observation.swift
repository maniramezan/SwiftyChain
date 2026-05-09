#if Observation
    public struct KeychainChangeEvent: Sendable, Hashable {
        public let service: String
        public let account: String?
        public let kind: Kind

        public enum Kind: Sendable, Hashable {
            case saved
            case updated
            case deleted
            case bulkDeleted
        }

        public init(service: String, account: String? = nil, kind: Kind) {
            self.service = service
            self.account = account
            self.kind = kind
        }
    }
#endif
