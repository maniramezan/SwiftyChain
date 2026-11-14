#if canImport(Security)
    import Foundation
    import Security
    import SwiftyChainCore

    /// The ``KeychainBackend`` for Apple platforms, backed by the Security framework.
    package struct AppleKeychainBackend: KeychainBackend {
        package let capabilities: KeychainBackendCapabilities

        package init() {
            self.capabilities = Self.platformCapabilities
        }

        /// What this OS's keychain supports.
        ///
        /// The SDK compiles every `SecItem` attribute on every Apple OS, so these limits
        /// come from the hardware and the services each OS runs, not from availability
        /// annotations: tvOS accepts `kSecAttrSynchronizable` but never syncs items
        /// through iCloud Keychain, and Apple TV has no biometry or device passcode.
        package static var platformCapabilities: KeychainBackendCapabilities {
            var capabilities: KeychainBackendCapabilities = [.accessGroups, .internetPasswords, .unscopedBulkDelete]
            #if !os(tvOS)
                capabilities.insert(.synchronizable)
            #endif
            #if Cryptography
                capabilities.insert(.cryptoKeys)
            #endif
            return capabilities
        }

        package func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {
            logSecurityCall("SecItemAdd", query: query)
            try mapStatus(SecItemAdd(addQuery(from: query, attributes: attributes) as CFDictionary, nil))
            SwiftyChainLoggers.backend.debug("SecItemAdd succeeded")
        }

        package func data(matching query: KeychainQuery) throws -> Data {
            logSecurityCall("SecItemCopyMatching", query: query)
            var secAttributes = matchQuery(from: query)
            secAttributes[kSecReturnData as String] = true
            secAttributes[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            try mapStatus(SecItemCopyMatching(secAttributes as CFDictionary, &result))
            guard let data = result as? Data else {
                SwiftyChainLoggers.backend.error("SecItemCopyMatching returned unexpected data result")
                throw KeychainError.unexpectedData
            }
            SwiftyChainLoggers.backend.debug("SecItemCopyMatching succeeded")
            return data
        }

        package func contains(matching query: KeychainQuery) throws -> Bool {
            logSecurityCall("SecItemCopyMatching", query: query)
            var secAttributes = matchQuery(from: query)
            secAttributes[kSecMatchLimit as String] = kSecMatchLimitOne
            let status = SecItemCopyMatching(secAttributes as CFDictionary, nil)
            if status == errSecItemNotFound {
                SwiftyChainLoggers.backend.debug("SecItemCopyMatching found no item")
                return false
            }
            try mapStatus(status)
            SwiftyChainLoggers.backend.debug("SecItemCopyMatching succeeded")
            return true
        }

        package func accounts(matching query: KeychainQuery) throws -> [String] {
            logSecurityCall("SecItemCopyMatching", query: query)
            var secAttributes = matchQuery(from: query)
            secAttributes[kSecReturnAttributes as String] = true
            secAttributes[kSecMatchLimit as String] = kSecMatchLimitAll

            var result: CFTypeRef?
            let status = SecItemCopyMatching(secAttributes as CFDictionary, &result)
            if status == errSecItemNotFound {
                SwiftyChainLoggers.backend.debug("SecItemCopyMatching found no items")
                return []
            }
            try mapStatus(status)
            guard let items = result as? [[String: Any]] else {
                SwiftyChainLoggers.backend.error("SecItemCopyMatching returned unexpected array result")
                throw KeychainError.unexpectedData
            }
            SwiftyChainLoggers.backend.debug("SecItemCopyMatching succeeded")
            return items.compactMap { $0[kSecAttrAccount as String] as? String }
        }

        package func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
            logSecurityCall("SecItemUpdate", query: query)
            let status = SecItemUpdate(
                matchQuery(from: query) as CFDictionary,
                updateAttributes(from: attributes) as CFDictionary
            )
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

        /// The dictionary `SecItemAdd` receives: the identity attributes plus every written value.
        package func addQuery(from query: KeychainQuery, attributes: KeychainAttributes) -> [String: Any] {
            var secAttributes = secQuery(from: query)
            secAttributes[kSecValueData as String] = attributes.data ?? Data()
            if let label = attributes.label {
                secAttributes[kSecAttrLabel as String] = label
            }
            if let comment = attributes.comment {
                secAttributes[kSecAttrComment as String] = comment
            }
            if let accessibility = attributes.accessibility {
                secAttributes[kSecAttrAccessible as String] = accessibility.secValue
            }
            return secAttributes
        }

        /// The dictionary of changes `SecItemUpdate` receives.
        package func updateAttributes(from attributes: KeychainAttributes) -> [String: Any] {
            var secAttributes: [String: Any] = [:]
            if let data = attributes.data {
                secAttributes[kSecValueData as String] = data
            }
            if let label = attributes.label {
                secAttributes[kSecAttrLabel as String] = label
            }
            if let comment = attributes.comment {
                secAttributes[kSecAttrComment as String] = comment
            }
            if let accessibility = attributes.accessibility {
                secAttributes[kSecAttrAccessible as String] = accessibility.secValue
            }
            return secAttributes
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

            return attributes
        }
        // swiftlint:enable cyclomatic_complexity

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
                SwiftyChainLoggers.backend.debug("Security operation missing entitlement")
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
        extension AppleKeychainBackend: KeychainCryptoBackend {
            package func addCryptoKey(
                _ key: SecKey, query: CryptoKeyQuery, attributes keyAttributes: CryptoKeyAttributes
            )
                throws
            {
                var attributes = cryptoSecQuery(from: query)
                attributes[kSecValueRef as String] = key
                if let accessibility = keyAttributes.accessibility {
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
#endif
