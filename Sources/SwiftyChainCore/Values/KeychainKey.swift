/// A typed descriptor that identifies a generic-password keychain item.
///
/// ``KeychainKey`` is parameterized by the ``KeychainStorable`` value type it
/// represents, providing compile-time type safety for all keychain operations.
/// The combination of `service` and `account` uniquely identifies an item
/// within an optional `accessGroup`.
///
/// ## Creating a key
///
/// ```swift
/// let tokenKey = KeychainKey<String>(
///     service: "com.example.app",
///     account: "auth-token"
/// )
///
/// let settingsKey = KeychainKey<Data>(
///     service: "com.example.app",
///     account: "user-settings",
///     accessibility: .afterFirstUnlock,
///     isSynchronizable: true
/// )
/// ```
public struct KeychainKey<Value: KeychainStorable>: Sendable, Hashable {
    /// The service attribute used to group related keychain items (e.g., your app's bundle ID).
    public let service: String
    /// The account attribute that distinguishes items within a service.
    public let account: String
    /// The access group for sharing items across apps, or `nil` for the app's default group.
    public let accessGroup: String?
    /// The accessibility policy that controls when this item can be read.
    public let accessibility: KeychainAccessibility
    /// Whether this item is synchronized to iCloud Keychain.
    public let isSynchronizable: Bool
    /// An optional human-readable label for the item displayed in Keychain Access.
    public let label: String?
    /// An optional comment attached to the item.
    public let comment: String?

    /// Creates a new keychain key descriptor.
    ///
    /// - Parameters:
    ///   - service: The service name that groups related items (e.g., your app's bundle ID).
    ///   - account: The account identifier (e.g., a username or key name).
    ///   - accessGroup: The access group for sharing items across apps. Defaults to `nil`.
    ///   - accessibility: Controls when the item is accessible. Defaults to ``KeychainAccessibility/whenUnlocked``.
    ///   - isSynchronizable: Pass `true` to sync this item via iCloud Keychain. Defaults to `false`.
    ///   - label: A human-readable label for the item. Defaults to `nil`.
    ///   - comment: A human-readable comment for the item. Defaults to `nil`.
    public init(
        service: String,
        account: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked,
        isSynchronizable: Bool = false,
        label: String? = nil,
        comment: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.accessibility = accessibility
        self.isSynchronizable = isSynchronizable
        self.label = label
        self.comment = comment
    }
}
