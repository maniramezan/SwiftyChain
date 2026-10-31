import Foundation

/// How many items a ``KeychainQuery`` returns from `copyMatching`.
package enum MatchLimit: Sendable, Hashable {
    case one
    case all
}

/// An attribute a backend reports for a matched item.
package enum KeychainAttribute: Sendable, Hashable {
    case account(String)
    case service(String)
}

/// A platform-neutral description of the items a backend operation targets.
///
/// A `nil` attribute places no constraint on matching items. When adding an item,
/// `nil` means the item is stored without that attribute.
package struct KeychainQuery: Sendable, Hashable {
    package let itemClass: KeychainItemClass
    package let service: String?
    package let account: String?
    package let accessGroup: String?
    package let accessibility: KeychainAccessibility?
    package let isSynchronizable: Bool?
    package let returnData: Bool
    package let returnAttributes: Bool
    package let matchLimit: MatchLimit
    package let server: String?
    package let port: Int?
    package let path: String?
    package let internetProtocol: InternetProtocol?
    package let authenticationType: AuthenticationType?
    package let label: String?
    package let comment: String?

    package init(
        itemClass: KeychainItemClass = .genericPassword,
        service: String? = nil,
        account: String? = nil,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility? = nil,
        isSynchronizable: Bool? = nil,
        returnData: Bool = false,
        returnAttributes: Bool = false,
        matchLimit: MatchLimit = .one,
        server: String? = nil,
        port: Int? = nil,
        path: String? = nil,
        internetProtocol: InternetProtocol? = nil,
        authenticationType: AuthenticationType? = nil,
        label: String? = nil,
        comment: String? = nil
    ) {
        self.itemClass = itemClass
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.accessibility = accessibility
        self.isSynchronizable = isSynchronizable
        self.returnData = returnData
        self.returnAttributes = returnAttributes
        self.matchLimit = matchLimit
        self.server = server
        self.port = port
        self.path = path
        self.internetProtocol = internetProtocol
        self.authenticationType = authenticationType
        self.label = label
        self.comment = comment
    }
}

/// The new values an `update` writes. `nil` leaves the stored value unchanged.
package struct KeychainAttributes: Sendable, Hashable {
    package let data: Data?
    package let label: String?
    package let comment: String?
    package let accessibility: KeychainAccessibility?

    package init(
        data: Data?,
        label: String?,
        comment: String?,
        accessibility: KeychainAccessibility?
    ) {
        self.data = data
        self.label = label
        self.comment = comment
        self.accessibility = accessibility
    }
}

/// The result of `copyMatching`.
///
/// A `.one` query returns ``data(_:)`` when it requests data, otherwise ``attributes(_:)``.
/// An `.all` query returns ``items(_:)`` holding one ``attributes(_:)`` entry per match.
package enum KeychainQueryResult: Sendable, Hashable {
    case data(Data)
    case attributes([KeychainAttribute])
    case items([KeychainQueryResult])
}
