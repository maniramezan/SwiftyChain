/// A typed descriptor that identifies a generic-password keychain item.
///
/// ``KeychainKey`` is parameterized by the ``KeychainStorable`` value type it
/// represents, providing compile-time type safety for all keychain operations.
/// The combination of `service` and `account` uniquely identifies an item
/// within an optional `accessGroup`.
///
/// Two keys are equal when they identify the same item: the same `service`,
/// `account`, `accessGroup`, and `isSynchronizable`. The write policy (`accessibility`,
/// `label`, and `comment`) controls how an item is stored, not which item it is.
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
    ///
    /// On Linux the access group is stored as an attribute that scopes lookups; it doesn't
    /// restrict which programs can read the item.
    public let accessGroup: String?
    /// The accessibility policy that controls when this item can be read, or `nil` to
    /// store new items with the platform default (``KeychainAccessibility/whenUnlocked``
    /// on Apple platforms) and leave an existing item's policy unchanged on update.
    public let accessibility: KeychainAccessibility?
    /// Authentication required when accessing the stored item.
    public let accessControl: KeychainAccessControl?
    /// Whether this item is synchronized to iCloud Keychain (Apple platforms only).
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
    ///   - accessibility: Controls when the item is accessible. Defaults to `nil`, which uses
    ///     the platform default for new items and keeps an existing item's policy on update.
    ///   - accessControl: Authentication required to access the item. Defaults to `nil`.
    ///   - isSynchronizable: Pass `true` to sync this item via iCloud Keychain. Defaults to `false`.
    ///     Apple platforms only; on Linux, `true` makes operations throw ``KeychainError/platformUnsupported(_:)``.
    ///   - label: A human-readable label for the item. Defaults to `nil`.
    ///   - comment: A human-readable comment for the item. Defaults to `nil`.
    public init(
        service: String,
        account: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility? = nil,
        accessControl: KeychainAccessControl? = nil,
        isSynchronizable: Bool = false,
        label: String? = nil,
        comment: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.accessibility = accessibility
        self.accessControl = accessControl
        self.isSynchronizable = isSynchronizable
        self.label = label
        self.comment = comment
    }

    /// Two keys are equal when they identify the same keychain item.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.service == rhs.service
            && lhs.account == rhs.account
            && lhs.accessGroup == rhs.accessGroup
            && lhs.isSynchronizable == rhs.isSynchronizable
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(service)
        hasher.combine(account)
        hasher.combine(accessGroup)
        hasher.combine(isSynchronizable)
    }
}
