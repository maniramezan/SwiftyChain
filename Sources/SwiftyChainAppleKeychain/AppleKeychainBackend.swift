import Foundation
import Security
import SwiftyChainCore

/// The ``SecureStorageBackend`` for Apple platforms, backed by the Security framework.
package struct AppleKeychainBackend: SecureStorageBackend {
    package let capabilities: SecureStorageCapabilities = .all

    package init() {}

    package func add(_ query: KeychainQuery, data: Data) throws {
        logSecurityCall("SecItemAdd", query: query)
        var attributes = secQuery(from: query)
        attributes[kSecValueData as String] = data
        if let accessibility = query.accessibility {
            attributes[kSecAttrAccessible as String] = accessibility.secValue
        }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        try mapStatus(status)
        SwiftyChainLoggers.backend.debug("SecItemAdd succeeded")
    }

    package func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        logSecurityCall("SecItemCopyMatching", query: query)
        var secAttributes = matchQuery(from: query)
        secAttributes[kSecReturnData as String] = query.returnData
        secAttributes[kSecReturnAttributes as String] = query.returnAttributes
        secAttributes[kSecMatchLimit as String] = query.matchLimit.secValue

        var result: CFTypeRef?
        let status = SecItemCopyMatching(secAttributes as CFDictionary, &result)
        try mapStatus(status)
        SwiftyChainLoggers.backend.debug("SecItemCopyMatching succeeded")

        if query.matchLimit == .all {
            guard let array = result as? [[String: Any]] else {
                SwiftyChainLoggers.backend.error("SecItemCopyMatching returned unexpected array result")
                throw KeychainError.unexpectedData
            }
            return .items(array.map { .attributes(attributes(from: $0)) })
        }

        if query.returnData {
            guard let data = result as? Data else {
                SwiftyChainLoggers.backend.error("SecItemCopyMatching returned unexpected data result")
                throw KeychainError.unexpectedData
            }
            return .data(data)
        }

        if query.returnAttributes {
            guard let dictionary = result as? [String: Any] else {
                SwiftyChainLoggers.backend.error("SecItemCopyMatching returned unexpected attributes result")
                throw KeychainError.unexpectedData
            }
            return .attributes(attributes(from: dictionary))
        }

        return .attributes([])
    }

    package func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        logSecurityCall("SecItemUpdate", query: query)
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

        let status = SecItemUpdate(matchQuery(from: query) as CFDictionary, updateAttributes as CFDictionary)
        try mapStatus(status)
        SwiftyChainLoggers.backend.debug("SecItemUpdate succeeded")
    }

    package func delete(matching query: KeychainQuery) throws {
        logSecurityCall("SecItemDelete", query: query)
        // The macOS legacy keychain removes one matching item per
        // SecItemDelete call, even when more match. Loop until the keychain
        // reports no more matches so bulk deletes actually clear everything.
        let attributes = matchQuery(from: query) as CFDictionary
        for _ in 0..<deleteSafetyCap {
            let status = SecItemDelete(attributes)
            if status == errSecItemNotFound {
                SwiftyChainLoggers.backend.debug("SecItemDelete completed")
                return
            }
            try mapStatus(status)
        }
        SwiftyChainLoggers.backend.fault(
            "SecItemDelete exceeded safety cap for itemClass=\(String(describing: query.itemClass), privacy: .public) service=\(query.service ?? "<none>", privacy: .private(mask: .hash)) account=\(query.account ?? "<none>", privacy: .private(mask: .hash)) server=\(query.server ?? "<none>", privacy: .private(mask: .hash))"
        )
        throw KeychainError.operationFailed(errSecInternalError)
    }

    private var deleteSafetyCap: Int { 10_000 }

    // Query used to find existing items. When the caller leaves
    // `isSynchronizable` unset, match both synchronizable and local items:
    // omitting kSecAttrSynchronizable makes Security.framework skip
    // iCloud Keychain items entirely.
    package func matchQuery(from query: KeychainQuery) -> [String: Any] {
        var attributes = secQuery(from: query)
        if query.isSynchronizable == nil {
            attributes[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }
        return attributes
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

    private func logSecurityCall(_ operation: StaticString, query: KeychainQuery) {
        SwiftyChainLoggers.backend.debug(
            "\(operation) started for itemClass=\(String(describing: query.itemClass), privacy: .public) service=\(query.service ?? "<none>", privacy: .private(mask: .hash)) account=\(query.account ?? "<none>", privacy: .private(mask: .hash)) server=\(query.server ?? "<none>", privacy: .private(mask: .hash))"
        )
    }

    private func mapStatus(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            SwiftyChainLoggers.backend.debug("Security operation returned item not found")
            throw KeychainError.itemNotFound
        case errSecDuplicateItem:
            SwiftyChainLoggers.backend.debug("Security operation returned duplicate item")
            throw KeychainError.duplicateItem
        case errSecAuthFailed, errSecUserCanceled:
            SwiftyChainLoggers.backend.debug("Security operation returned authentication failure")
            throw KeychainError.authenticationFailed
        case errSecInteractionNotAllowed:
            SwiftyChainLoggers.backend.debug("Security operation requires user presence")
            throw KeychainError.userPresenceRequired
        case errSecMissingEntitlement:
            SwiftyChainLoggers.backend.error("Security operation missing entitlement")
            throw KeychainError.accessGroupDenied
        default:
            SwiftyChainLoggers.backend.error("Security operation failed with status=\(status, privacy: .public)")
            throw KeychainError.operationFailed(status)
        }
    }
}

extension KeychainAccessibility {
    package var secValue: CFString {
        switch self {
        case .afterFirstUnlock:
            kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly:
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlocked:
            kSecAttrAccessibleWhenUnlocked
        case .whenUnlockedThisDeviceOnly:
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly:
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
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
        switch kind {
        case .genericPassword:
            kSecClassGenericPassword
        case .internetPassword:
            kSecClassInternetPassword
        case .cryptographicKey:
            kSecClassKey
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
        package func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery) throws {
            var attributes = cryptoSecQuery(from: query)
            attributes[kSecValueRef as String] = key
            if let accessibility = query.accessibility {
                attributes[kSecAttrAccessible as String] = accessibility.secValue
            }
            let status = SecItemAdd(attributes as CFDictionary, nil)
            try mapStatus(status)
        }

        package func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey {
            var attributes = cryptoSecQuery(from: query)
            attributes[kSecReturnRef as String] = true
            attributes[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(attributes as CFDictionary, &result)
            try mapStatus(status)

            guard let result, CFGetTypeID(result) == SecKeyGetTypeID() else {
                throw KeychainError.unexpectedData
            }
            // Safe: type ID verified above; CFTypeRef-to-SecKey cast always
            // succeeds for CF types so `as?` is rejected by the compiler.
            return result as! SecKey
        }

        package func deleteCryptoKey(query: CryptoKeyQuery) throws {
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
