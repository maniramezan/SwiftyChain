/// Filter structure for flexible bulk deletion.
///
/// Use a ``KeychainDeleteQuery`` to describe a set of keychain items to remove
/// in a single call to ``Keychain/deleteAllItems(matching:)``.
///
/// Two factory methods cover the most common cases:
/// - ``allItems(service:accessGroup:)`` — removes every item for a service.
/// - ``synchronizableItems(service:accessGroup:)`` — removes only iCloud-synced items.
///
/// ```swift
/// // Remove all items for a service
/// try await Keychain.shared.deleteAllItems(matching: .allItems(service: "com.example.app"))
///
/// // Remove only iCloud-synced items
/// try await Keychain.shared.deleteAllItems(
///     matching: .synchronizableItems(service: "com.example.app")
/// )
/// ```
public struct KeychainDeleteQuery: Sendable, Hashable {
    /// The service to filter by, or `nil` to match items across all services.
    public let service: String?
    /// The access group to filter by, or `nil` for the default group.
    public let accessGroup: String?
    /// When `true`, iCloud-synchronized items are included in the deletion. Defaults to `true`.
    public let includeSynchronizable: Bool
    /// When `true`, only iCloud-synchronized items are deleted; non-synchronizable items are left intact.
    public let onlySynchronizable: Bool
    /// The item class to target. Defaults to ``KeychainItemClass/genericPassword``.
    public let itemClass: KeychainItemClass

    /// Creates a new bulk-delete query.
    ///
    /// - Parameters:
    ///   - service: The service to match. Pass `nil` to delete across all services.
    ///   - accessGroup: The access group to match. Pass `nil` for the default group.
    ///   - includeSynchronizable: Include iCloud-synchronized items. Defaults to `true`.
    ///   - onlySynchronizable: Delete only iCloud-synchronized items. Defaults to `false`.
    ///   - itemClass: The keychain item class to target. Defaults to ``KeychainItemClass/genericPassword``.
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

    /// Creates a query that matches all items (synchronizable and non-synchronizable) for a service.
    ///
    /// - Parameters:
    ///   - service: The service whose items should be deleted.
    ///   - accessGroup: The access group. Pass `nil` for the default group.
    public static func allItems(
        service: String,
        accessGroup: String? = nil
    ) -> KeychainDeleteQuery {
        KeychainDeleteQuery(service: service, accessGroup: accessGroup)
    }

    /// Creates a query that matches only iCloud-synchronized items for a service.
    ///
    /// Non-synchronizable items are left untouched.
    ///
    /// - Parameters:
    ///   - service: The service whose synchronizable items should be deleted.
    ///   - accessGroup: The access group. Pass `nil` for the default group.
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
