import Foundation

internal enum MatchLimit: Sendable, Hashable {
    case one
    case all
}

internal enum KeychainAttribute: Sendable, Hashable {
    case account(String)
    case service(String)
}

internal struct KeychainQuery: Sendable, Hashable {
    let itemClass: KeychainItemClass
    let service: String?
    let account: String?
    let accessGroup: String?
    let accessibility: KeychainAccessibility?
    let isSynchronizable: Bool?
    let returnData: Bool
    let returnAttributes: Bool
    let matchLimit: MatchLimit
    let server: String?
    let port: Int?
    let path: String?
    let internetProtocol: InternetProtocol?
    let authenticationType: AuthenticationType?
    let label: String?
    let comment: String?

    init(
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

internal struct KeychainAttributes: Sendable, Hashable {
    let data: Data?
    let label: String?
    let comment: String?
    let accessibility: KeychainAccessibility?
}

internal enum KeychainQueryResult: Sendable, Hashable {
    case data(Data)
    case attributes([KeychainAttribute])
    case items([KeychainQueryResult])
}

internal protocol SecureStorageBackend: Sendable {
    func add(_ query: KeychainQuery, data: Data) throws
    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult
    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws
    func delete(matching query: KeychainQuery) throws
}

#if Cryptography
    import Security

    /// Query descriptor for cryptographic key operations.
    internal struct CryptoKeyQuery: Sendable, Hashable {
        let tag: String
        let accessGroup: String?
        let accessibility: KeychainAccessibility?
    }

    /// Backend protocol for SecKey storage, separated from the generic backend
    /// because SecKey is not Sendable/Hashable and cannot flow through KeychainQuery.
    internal protocol CryptoStorageBackend: Sendable {
        func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery) throws
        func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey
        func deleteCryptoKey(query: CryptoKeyQuery) throws
    }
#endif
