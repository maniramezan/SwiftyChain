/// A typed descriptor for a keychain item.
public struct KeychainKey<Value: KeychainStorable>: Sendable, Hashable {
    public let service: String
    public let account: String
    public let accessGroup: String?
    public let accessibility: KeychainAccessibility
    public let isSynchronizable: Bool
    public let label: String?
    public let comment: String?

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
