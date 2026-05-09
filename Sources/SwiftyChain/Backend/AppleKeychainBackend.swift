import Foundation
import Security

internal struct AppleKeychainBackend: SecureStorageBackend {
    func add(_ query: KeychainQuery, data: Data) throws {
        var attributes = secQuery(from: query)
        attributes[kSecValueData as String] = data
        if let accessibility = query.accessibility {
            attributes[kSecAttrAccessible as String] = accessibility.secValue
        }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        try mapStatus(status)
    }

    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        var secAttributes = secQuery(from: query)
        secAttributes[kSecReturnData as String] = query.returnData
        secAttributes[kSecReturnAttributes as String] = query.returnAttributes
        secAttributes[kSecMatchLimit as String] = query.matchLimit.secValue

        var result: CFTypeRef?
        let status = SecItemCopyMatching(secAttributes as CFDictionary, &result)
        try mapStatus(status)

        if query.matchLimit == .all {
            guard let array = result as? [[String: Any]] else {
                throw KeychainError.unexpectedData
            }
            return .items(array.map { .attributes(attributes(from: $0)) })
        }

        if query.returnData {
            guard let data = result as? Data else {
                throw KeychainError.unexpectedData
            }
            return .data(data)
        }

        if query.returnAttributes {
            guard let dictionary = result as? [String: Any] else {
                throw KeychainError.unexpectedData
            }
            return .attributes(attributes(from: dictionary))
        }

        return .attributes([])
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        var updateAttributes: [String: Any] = [:]
        if let data = attributes.data {
            updateAttributes[kSecValueData as String] = data
        }
        if let label = attributes.label {
            updateAttributes[kSecAttrLabel as String] = label
        }
        if let comment = attributes.comment {
            updateAttributes[kSecAttrComment as String] = comment
        }
        if let accessibility = attributes.accessibility {
            updateAttributes[kSecAttrAccessible as String] = accessibility.secValue
        }

        let status = SecItemUpdate(secQuery(from: query) as CFDictionary, updateAttributes as CFDictionary)
        try mapStatus(status)
    }

    func delete(matching query: KeychainQuery) throws {
        let status = SecItemDelete(secQuery(from: query) as CFDictionary)
        if status == errSecItemNotFound {
            return
        }
        try mapStatus(status)
    }

    // This keychain query is assembled from many optional fields on purpose.
    // Keeping the mapping centralized avoids diverging Security.framework call sites.
    // swiftlint:disable cyclomatic_complexity
    private func secQuery(from query: KeychainQuery) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecClass as String: query.itemClass.secValue
        ]

        if let service = query.service {
            attributes[kSecAttrService as String] = service
        }
        if let account = query.account {
            attributes[kSecAttrAccount as String] = account
        }
        if let accessGroup = query.accessGroup {
            attributes[kSecAttrAccessGroup as String] = accessGroup
        }
        if let isSynchronizable = query.isSynchronizable {
            attributes[kSecAttrSynchronizable as String] = isSynchronizable ? kCFBooleanTrue : kCFBooleanFalse
        }
        if let server = query.server {
            attributes[kSecAttrServer as String] = server
        }
        if let port = query.port {
            attributes[kSecAttrPort as String] = port
        }
        if let path = query.path {
            attributes[kSecAttrPath as String] = path
        }
        if let internetProtocol = query.internetProtocol {
            attributes[kSecAttrProtocol as String] = internetProtocol.secValue
        }
        if let authenticationType = query.authenticationType {
            attributes[kSecAttrAuthenticationType as String] = authenticationType.secValue
        }
        if let label = query.label {
            attributes[kSecAttrLabel as String] = label
        }
        if let comment = query.comment {
            attributes[kSecAttrComment as String] = comment
        }

        return attributes
    }
    // swiftlint:enable cyclomatic_complexity

    private func attributes(from dictionary: [String: Any]) -> [KeychainAttribute] {
        var values: [KeychainAttribute] = []
        if let account = dictionary[kSecAttrAccount as String] as? String {
            values.append(.account(account))
        }
        if let service = dictionary[kSecAttrService as String] as? String {
            values.append(.service(service))
        }
        return values
    }

    private func mapStatus(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        case errSecAuthFailed, errSecUserCanceled:
            throw KeychainError.authenticationFailed
        case errSecInteractionNotAllowed:
            throw KeychainError.userPresenceRequired
        case errSecMissingEntitlement:
            throw KeychainError.accessGroupDenied
        default:
            throw KeychainError.operationFailed(status)
        }
    }
}

extension MatchLimit {
    fileprivate var secValue: CFString {
        switch self {
        case .one:
            kSecMatchLimitOne
        case .all:
            kSecMatchLimitAll
        }
    }
}

extension KeychainItemClass {
    fileprivate var secValue: CFString {
        switch self {
        case .genericPassword:
            kSecClassGenericPassword
        case .internetPassword:
            kSecClassInternetPassword
        #if Cryptography
            case .cryptographicKey:
                kSecClassKey
        #endif
        }
    }
}

extension InternetProtocol {
    fileprivate var secValue: CFString {
        switch self {
        case .ftp: kSecAttrProtocolFTP
        case .ftpAccount: kSecAttrProtocolFTPAccount
        case .http: kSecAttrProtocolHTTP
        case .irc: kSecAttrProtocolIRC
        case .nntp: kSecAttrProtocolNNTP
        case .pop3: kSecAttrProtocolPOP3
        case .smtp: kSecAttrProtocolSMTP
        case .socks: kSecAttrProtocolSOCKS
        case .imap: kSecAttrProtocolIMAP
        case .ldap: kSecAttrProtocolLDAP
        case .appleTalk: kSecAttrProtocolAppleTalk
        case .afp: kSecAttrProtocolAFP
        case .telnet: kSecAttrProtocolTelnet
        case .ssh: kSecAttrProtocolSSH
        case .ftps: kSecAttrProtocolFTPS
        case .https: kSecAttrProtocolHTTPS
        case .httpProxy: kSecAttrProtocolHTTPProxy
        case .httpsProxy: kSecAttrProtocolHTTPSProxy
        case .ftpProxy: kSecAttrProtocolFTPProxy
        case .smb: kSecAttrProtocolSMB
        case .rtsp: kSecAttrProtocolRTSP
        case .rtspProxy: kSecAttrProtocolRTSPProxy
        case .daap: kSecAttrProtocolDAAP
        case .eppc: kSecAttrProtocolEPPC
        case .ipp: kSecAttrProtocolIPP
        case .nntps: kSecAttrProtocolNNTPS
        case .ldaps: kSecAttrProtocolLDAPS
        case .telnetS: kSecAttrProtocolTelnetS
        case .imaps: kSecAttrProtocolIMAPS
        case .ircs: kSecAttrProtocolIRCS
        case .pop3S: kSecAttrProtocolPOP3S
        }
    }
}

extension AuthenticationType {
    fileprivate var secValue: CFString {
        switch self {
        case .ntlm: kSecAttrAuthenticationTypeNTLM
        case .msn: kSecAttrAuthenticationTypeMSN
        case .dpa: kSecAttrAuthenticationTypeDPA
        case .rpa: kSecAttrAuthenticationTypeRPA
        case .httpBasic: kSecAttrAuthenticationTypeHTTPBasic
        case .httpDigest: kSecAttrAuthenticationTypeHTTPDigest
        case .htmlForm: kSecAttrAuthenticationTypeHTMLForm
        case .default: kSecAttrAuthenticationTypeDefault
        }
    }
}

#if Cryptography
    extension AppleKeychainBackend: CryptoStorageBackend {
        func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery) throws {
            var attributes = cryptoSecQuery(from: query)
            attributes[kSecValueRef as String] = key
            if let accessibility = query.accessibility {
                attributes[kSecAttrAccessible as String] = accessibility.secValue
            }
            let status = SecItemAdd(attributes as CFDictionary, nil)
            try mapStatus(status)
        }

        func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey {
            var attributes = cryptoSecQuery(from: query)
            attributes[kSecReturnRef as String] = true
            attributes[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(attributes as CFDictionary, &result)
            try mapStatus(status)

            guard let secKey = result as? SecKey else {
                throw KeychainError.unexpectedData
            }
            return secKey
        }

        func deleteCryptoKey(query: CryptoKeyQuery) throws {
            let status = SecItemDelete(cryptoSecQuery(from: query) as CFDictionary)
            if status == errSecItemNotFound { return }
            try mapStatus(status)
        }

        private func cryptoSecQuery(from query: CryptoKeyQuery) -> [String: Any] {
            var attributes: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: Data(query.tag.utf8),
            ]
            if let accessGroup = query.accessGroup {
                attributes[kSecAttrAccessGroup as String] = accessGroup
            }
            return attributes
        }
    }
#endif
