import Foundation
import SwiftyChainCore

/// The libsecret schema an item is stored under. The schema name is stored with every
/// item as `xdg:schema`, so SwiftyChain's queries never match other applications' items.
package enum SecretServiceSchema: Sendable, Hashable {
    case genericPassword
    case internetPassword

    package var name: String {
        switch self {
        case .genericPassword: "dev.manman.SwiftyChain.GenericPassword"
        case .internetPassword: "dev.manman.SwiftyChain.InternetPassword"
        }
    }

    /// Attribute names in the order the C schema declares them.
    package var attributeNames: [String] {
        switch self {
        case .genericPassword:
            ["service", "account", "accessGroup"]
        case .internetPassword:
            ["server", "account", "port", "path", "protocol", "authenticationType", "accessGroup"]
        }
    }
}

/// A schema plus the attributes that select items within it.
package struct SecretServiceItemQuery: Sendable, Hashable {
    package let schema: SecretServiceSchema
    package let attributes: [String: String]
}

/// Maps platform-neutral ``KeychainQuery`` values to Secret Service attributes.
///
/// Secret Service matches an item when it has every attribute in the query, so a
/// query with fewer attributes matches more items. New items always store every
/// schema attribute, using an empty value (or `0` for the port) when the key
/// leaves one unset. A query built with ``identity(for:)`` therefore selects exactly
/// one item, while ``matching(_:)`` omits unset fields so they match any value.
package enum SecretServiceAttributes {
    /// The schema for an item class.
    ///
    /// - Throws: ``KeychainError/platformUnsupported(_:)`` for cryptographic keys, which
    ///   the Secret Service backend can't store.
    package static func schema(for itemClass: KeychainItemClass) throws -> SecretServiceSchema {
        switch itemClass.kind {
        case .genericPassword:
            return .genericPassword
        case .internetPassword:
            return .internetPassword
        case .cryptographicKey:
            SwiftyChainLoggers.backend.debug("Secret Service rejected a cryptographic key query")
            throw KeychainError.platformUnsupported("Cryptographic keys are not supported by this keychain backend")
        }
    }

    /// Attributes selecting every stored item the query describes.
    package static func matching(_ query: KeychainQuery) throws -> SecretServiceItemQuery {
        let schema = try schema(for: query.itemClass)
        var attributes: [String: String] = [:]
        switch schema {
        case .genericPassword:
            attributes["service"] = query.service
            attributes["account"] = query.account
        case .internetPassword:
            attributes["server"] = query.server
            attributes["account"] = query.account
            attributes["port"] = query.port.map(String.init)
            attributes["path"] = query.path
            attributes["protocol"] = query.internetProtocol.map(storedValue)
            attributes["authenticationType"] = query.authenticationType.map(storedValue)
        }
        attributes["accessGroup"] = query.accessGroup
        return SecretServiceItemQuery(schema: schema, attributes: attributes)
    }

    /// Whether a delete with these attributes is limited to one app's items.
    ///
    /// Every app built on SwiftyChain shares the same schemas, so a delete must name
    /// something that belongs to the caller: a non-empty service (or server, for
    /// internet passwords) or access group, or an exact item, meaning a service or
    /// server together with an account. Only the schema's own attributes count,
    /// because ``matching(_:)`` drops the rest; a generic-password query that names
    /// only a server would otherwise match every generic password.
    package static func isScopedForDeletion(_ query: SecretServiceItemQuery) -> Bool {
        let primary =
            switch query.schema {
            case .genericPassword: query.attributes["service"]
            case .internetPassword: query.attributes["server"]
            }
        if let primary, !primary.isEmpty {
            return true
        }
        if let accessGroup = query.attributes["accessGroup"], !accessGroup.isEmpty {
            return true
        }
        return primary != nil && query.attributes["account"] != nil
    }

    /// The complete attribute set stored with a new item.
    package static func identity(for query: KeychainQuery) throws -> SecretServiceItemQuery {
        let schema = try schema(for: query.itemClass)
        var attributes: [String: String] = [:]
        switch schema {
        case .genericPassword:
            attributes["service"] = query.service ?? ""
            attributes["account"] = query.account ?? ""
        case .internetPassword:
            attributes["server"] = query.server ?? ""
            attributes["account"] = query.account ?? ""
            attributes["port"] = String(query.port ?? 0)
            attributes["path"] = query.path ?? ""
            attributes["protocol"] = query.internetProtocol.map(storedValue) ?? ""
            attributes["authenticationType"] = query.authenticationType.map(storedValue) ?? ""
        }
        attributes["accessGroup"] = query.accessGroup ?? ""
        return SecretServiceItemQuery(schema: schema, attributes: attributes)
    }

    /// The label shown for a new item in keyring managers such as Seahorse: `custom` when
    /// the caller set one, otherwise one derived from the query.
    package static func label(for query: KeychainQuery, custom: String?) throws -> String {
        if let label = custom {
            return label
        }
        switch try schema(for: query.itemClass) {
        case .genericPassword:
            return "\(query.service ?? "") (\(query.account ?? ""))"
        case .internetPassword:
            return "\(query.account ?? "")@\(query.server ?? "")"
        }
    }

    // These strings are persisted in users' keyrings. Never change an existing value.
    package static func storedValue(_ internetProtocol: InternetProtocol) -> String {
        switch internetProtocol {
        case .ftp: "ftp"
        case .ftpAccount: "ftp-account"
        case .http: "http"
        case .irc: "irc"
        case .nntp: "nntp"
        case .pop3: "pop3"
        case .smtp: "smtp"
        case .socks: "socks"
        case .imap: "imap"
        case .ldap: "ldap"
        case .appleTalk: "appletalk"
        case .afp: "afp"
        case .telnet: "telnet"
        case .ssh: "ssh"
        case .ftps: "ftps"
        case .https: "https"
        case .httpProxy: "http-proxy"
        case .httpsProxy: "https-proxy"
        case .ftpProxy: "ftp-proxy"
        case .smb: "smb"
        case .rtsp: "rtsp"
        case .rtspProxy: "rtsp-proxy"
        case .daap: "daap"
        case .eppc: "eppc"
        case .ipp: "ipp"
        case .nntps: "nntps"
        case .ldaps: "ldaps"
        case .telnetS: "telnets"
        case .imaps: "imaps"
        case .ircs: "ircs"
        case .pop3S: "pop3s"
        }
    }

    // These strings are persisted in users' keyrings. Never change an existing value.
    package static func storedValue(_ authenticationType: AuthenticationType) -> String {
        switch authenticationType {
        case .ntlm: "ntlm"
        case .msn: "msn"
        case .dpa: "dpa"
        case .rpa: "rpa"
        case .httpBasic: "http-basic"
        case .httpDigest: "http-digest"
        case .htmlForm: "html-form"
        case .default: "default"
        }
    }
}
