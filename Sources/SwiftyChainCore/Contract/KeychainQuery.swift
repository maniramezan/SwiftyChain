import Foundation

/// A platform-neutral description of the items a ``KeychainBackend`` operation targets.
///
/// A query only selects items. Values that are written, such as the secret itself, a
/// label, or an accessibility policy, travel separately in ``KeychainAttributes``.
///
/// A `nil` attribute places no constraint on matching items, and `isSynchronizable == nil`
/// matches both synchronizable and local items. When ``KeychainBackend/add(_:attributes:)``
/// receives a query, `nil` means the item is stored without that attribute, and a `nil`
/// `isSynchronizable` stores a local item.
public struct KeychainQuery: Sendable, Hashable {
    /// The item class to match.
    public let itemClass: KeychainItemClass
    /// The service of a generic password.
    public let service: String?
    /// The account of a generic or internet password.
    public let account: String?
    /// The access group the item belongs to.
    public let accessGroup: String?
    /// Whether the item syncs through iCloud Keychain, or `nil` to match either.
    public let isSynchronizable: Bool?
    /// The server of an internet password.
    public let server: String?
    /// The port of an internet password.
    public let port: Int?
    /// The path of an internet password.
    public let path: String?
    /// The protocol of an internet password.
    public let internetProtocol: InternetProtocol?
    /// The authentication type of an internet password.
    public let authenticationType: AuthenticationType?

    /// Creates a query. Every attribute defaults to `nil`, which matches any value.
    public init(
        itemClass: KeychainItemClass = .genericPassword,
        service: String? = nil,
        account: String? = nil,
        accessGroup: String? = nil,
        isSynchronizable: Bool? = nil,
        server: String? = nil,
        port: Int? = nil,
        path: String? = nil,
        internetProtocol: InternetProtocol? = nil,
        authenticationType: AuthenticationType? = nil
    ) {
        self.itemClass = itemClass
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.isSynchronizable = isSynchronizable
        self.server = server
        self.port = port
        self.path = path
        self.internetProtocol = internetProtocol
        self.authenticationType = authenticationType
    }
}

/// The values ``KeychainBackend/add(_:attributes:)`` stores and
/// ``KeychainBackend/update(matching:to:)`` writes.
///
/// On `update`, a `nil` value leaves the stored value unchanged. On `add`, a `nil` value
/// stores the platform default, and ``data`` is always set.
public struct KeychainAttributes: Sendable, Hashable {
    /// The secret.
    public let data: Data?
    /// A human-readable label.
    public let label: String?
    /// A human-readable comment.
    public let comment: String?
    /// When the item can be read.
    public let accessibility: KeychainAccessibility?
    /// Authentication required when accessing the stored item.
    public let accessControl: KeychainAccessControl?

    /// Creates a set of attributes. Every value defaults to `nil`.
    public init(
        data: Data? = nil,
        label: String? = nil,
        comment: String? = nil,
        accessibility: KeychainAccessibility? = nil,
        accessControl: KeychainAccessControl? = nil
    ) {
        self.data = data
        self.label = label
        self.comment = comment
        self.accessibility = accessibility
        self.accessControl = accessControl
    }
}
