/// Internet protocol values for a `kSecClassInternetPassword` keychain item.
///
/// Passed to ``InternetPasswordKey`` to identify the protocol used to access
/// the server whose credentials are being stored.
public enum InternetProtocol: Sendable, Hashable {
    /// File Transfer Protocol.
    case ftp
    /// FTP account credentials.
    case ftpAccount
    /// Hypertext Transfer Protocol.
    case http
    /// Internet Relay Chat.
    case irc
    /// Network News Transfer Protocol.
    case nntp
    /// Post Office Protocol version 3.
    case pop3
    /// Simple Mail Transfer Protocol.
    case smtp
    /// SOCKS proxy protocol.
    case socks
    /// Internet Message Access Protocol.
    case imap
    /// Lightweight Directory Access Protocol.
    case ldap
    /// AppleTalk.
    case appleTalk
    /// Apple Filing Protocol.
    case afp
    /// Telnet.
    case telnet
    /// Secure Shell.
    case ssh
    /// FTP over TLS/SSL.
    case ftps
    /// HTTP over TLS/SSL.
    case https
    /// HTTP proxy.
    case httpProxy
    /// HTTPS proxy.
    case httpsProxy
    /// FTP proxy.
    case ftpProxy
    /// Server Message Block.
    case smb
    /// Real Time Streaming Protocol.
    case rtsp
    /// RTSP proxy.
    case rtspProxy
    /// Digital Audio Access Protocol.
    case daap
    /// Remote Apple Events.
    case eppc
    /// Internet Printing Protocol.
    case ipp
    /// NNTP over TLS/SSL.
    case nntps
    /// LDAP over TLS/SSL.
    case ldaps
    /// Telnet over TLS/SSL.
    case telnetS
    /// IMAP over TLS/SSL.
    case imaps
    /// IRC over TLS/SSL.
    case ircs
    /// POP3 over TLS/SSL.
    case pop3S
}

/// Authentication methods for a `kSecClassInternetPassword` keychain item.
///
/// Passed to ``InternetPasswordKey`` to identify how the client authenticates
/// with the server whose credentials are being stored.
public enum AuthenticationType: Sendable, Hashable {
    /// NT LAN Manager authentication.
    case ntlm
    /// Microsoft Network authentication.
    case msn
    /// Distributed Password Authentication.
    case dpa
    /// Remote Password Authentication.
    case rpa
    /// HTTP Basic authentication.
    case httpBasic
    /// HTTP Digest authentication.
    case httpDigest
    /// HTML form-based authentication.
    case htmlForm
    /// The default authentication type for the protocol.
    case `default`
}

/// A typed descriptor for an internet password keychain item.
///
/// Use ``InternetPasswordKey`` to store and retrieve credentials for a specific
/// server and account via ``Keychain``.
///
/// ```swift
/// let key = InternetPasswordKey(
///     server: "api.example.com",
///     account: "user@example.com",
///     protocol: .https,
///     authenticationType: .httpBasic
/// )
/// try await Keychain.shared.saveInternetPassword("s3cr3t", for: key)
/// let password = try await Keychain.shared.loadInternetPassword(for: key)
/// ```
///
/// Two keys are equal when they identify the same item. `accessibility` controls how an
/// item is stored, not which item it is, so it doesn't take part.
public struct InternetPasswordKey: Sendable, Hashable {
    /// The server hostname (e.g., `"api.example.com"`).
    public let server: String
    /// The account identifier (e.g., a username or email address).
    public let account: String
    /// The server port, or `nil` to use the default port for the protocol.
    public let port: Int?
    /// The URL path component, or `nil` for the root path.
    public let path: String?
    /// The internet protocol used to communicate with the server.
    public let `protocol`: InternetProtocol
    /// The authentication type used with the server.
    public let authenticationType: AuthenticationType
    /// The access group for sharing across apps, or `nil` for the default group.
    public let accessGroup: String?
    /// The accessibility policy for this item, or `nil` for the platform default.
    public let accessibility: KeychainAccessibility?
    /// Authentication required when accessing the stored item.
    public let accessControl: KeychainAccessControl?

    /// Creates an internet password key descriptor.
    ///
    /// - Parameters:
    ///   - server: The server hostname.
    ///   - account: The account identifier.
    ///   - port: The server port. Defaults to `nil` (protocol default).
    ///   - path: The URL path. Defaults to `nil`.
    ///   - protocol: The internet protocol. Defaults to ``InternetProtocol/https``.
    ///   - authenticationType: The authentication type. Defaults to ``AuthenticationType/default``.
    ///   - accessGroup: The keychain access group. Defaults to `nil`.
    ///   - accessibility: The accessibility policy. Defaults to `nil`, the platform default.
    public init(
        server: String,
        account: String,
        port: Int? = nil,
        path: String? = nil,
        protocol: InternetProtocol = .https,
        authenticationType: AuthenticationType = .default,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility? = nil,
        accessControl: KeychainAccessControl? = nil
    ) {
        self.server = server
        self.account = account
        self.port = port
        self.path = path
        self.protocol = `protocol`
        self.authenticationType = authenticationType
        self.accessGroup = accessGroup
        self.accessibility = accessibility
        self.accessControl = accessControl
    }

    /// Two keys are equal when they identify the same keychain item.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.server == rhs.server
            && lhs.account == rhs.account
            && lhs.port == rhs.port
            && lhs.path == rhs.path
            && lhs.protocol == rhs.protocol
            && lhs.authenticationType == rhs.authenticationType
            && lhs.accessGroup == rhs.accessGroup
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(server)
        hasher.combine(account)
        hasher.combine(port)
        hasher.combine(path)
        hasher.combine(`protocol`)
        hasher.combine(authenticationType)
        hasher.combine(accessGroup)
    }
}
