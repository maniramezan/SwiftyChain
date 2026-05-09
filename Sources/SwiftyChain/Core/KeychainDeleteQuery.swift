/// Filter structure for flexible bulk deletion.
public struct KeychainDeleteQuery: Sendable, Hashable {
    public let service: String?
    public let accessGroup: String?
    public let includeSynchronizable: Bool
    public let onlySynchronizable: Bool
    public let itemClass: KeychainItemClass

    public init(
        service: String? = nil,
        accessGroup: String? = nil,
        includeSynchronizable: Bool = true,
        onlySynchronizable: Bool = false,
        itemClass: KeychainItemClass = .genericPassword
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.includeSynchronizable = includeSynchronizable
        self.onlySynchronizable = onlySynchronizable
        self.itemClass = itemClass
    }

    public static func allItems(
        service: String,
        accessGroup: String? = nil
    ) -> KeychainDeleteQuery {
        KeychainDeleteQuery(service: service, accessGroup: accessGroup)
    }

    public static func synchronizableItems(
        service: String,
        accessGroup: String? = nil
    ) -> KeychainDeleteQuery {
        KeychainDeleteQuery(
            service: service,
            accessGroup: accessGroup,
            onlySynchronizable: true
        )
    }
}
