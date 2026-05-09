/// Internet protocol values supported by `kSecClassInternetPassword`.
public enum InternetProtocol: Sendable, Hashable {
    case ftp
    case ftpAccount
    case http
    case irc
    case nntp
    case pop3
    case smtp
    case socks
    case imap
    case ldap
    case appleTalk
    case afp
    case telnet
    case ssh
    case ftps
    case https
    case httpProxy
    case httpsProxy
    case ftpProxy
    case smb
    case rtsp
    case rtspProxy
    case daap
    case eppc
    case ipp
    case nntps
    case ldaps
    case telnetS
    case imaps
    case ircs
    case pop3S
}

/// Authentication types supported by `kSecClassInternetPassword`.
public enum AuthenticationType: Sendable, Hashable {
    case ntlm
    case msn
    case dpa
    case rpa
    case httpBasic
    case httpDigest
    case htmlForm
    case `default`
}

/// A typed descriptor for an internet password keychain item.
public struct InternetPasswordKey: Sendable, Hashable {
    public let server: String
    public let account: String
    public let port: Int?
    public let path: String?
    public let `protocol`: InternetProtocol
    public let authenticationType: AuthenticationType
    public let accessGroup: String?
    public let accessibility: KeychainAccessibility

    public init(
        server: String,
        account: String,
        port: Int? = nil,
        path: String? = nil,
        protocol: InternetProtocol = .https,
        authenticationType: AuthenticationType = .default,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked
    ) {
        self.server = server
        self.account = account
        self.port = port
        self.path = path
        self.protocol = `protocol`
        self.authenticationType = authenticationType
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }
}
