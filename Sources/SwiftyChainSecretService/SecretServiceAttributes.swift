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
    package static func schema(for itemClass: KeychainItemClass) -> SecretServiceSchema {
        itemClass == .internetPassword ? .internetPassword : .genericPassword
    }

    /// Attributes selecting every stored item the query describes.
    package static func matching(_ query: KeychainQuery) -> SecretServiceItemQuery {
        let schema = schema(for: query.itemClass)
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

    /// The complete attribute set stored with a new item.
    package static func identity(for query: KeychainQuery) -> SecretServiceItemQuery {
        let schema = schema(for: query.itemClass)
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

    /// The label shown for a new item in keyring managers such as Seahorse.
    package static func label(for query: KeychainQuery) -> String {
        if let label = query.label {
            return label
        }
        switch schema(for: query.itemClass) {
        case .genericPassword:
            return "\(query.service ?? "") (\(query.account ?? ""))"
        case .internetPassword:
            return "\(query.account ?? "")@\(query.server ?? "")"
        }
    }

    /// The attributes SwiftyChain reports for a stored item.
    package static func keychainAttributes(from stored: [String: String]) -> [KeychainAttribute] {
        [stored["account"].map(KeychainAttribute.account), stored["service"].map(KeychainAttribute.service)]
            .compactMap { $0 }
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
