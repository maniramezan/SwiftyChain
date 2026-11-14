#if canImport(Security)
    import Foundation
    import Security
    import SwiftyChainCore

    #if canImport(LocalAuthentication)
        import LocalAuthentication
    #endif

    /// The ``KeychainBackend`` for Apple platforms, backed by the Security framework.
    package struct AppleKeychainBackend: KeychainBackend {
        package let capabilities: KeychainBackendCapabilities

        private let configuration: KeychainConfiguration

        package init(configuration: KeychainConfiguration = .init()) {
            self.configuration = configuration
            var capabilities = Self.platformCapabilities
            #if os(macOS)
                if configuration.macOSStore == .dataProtection {
                    capabilities.insert(.accessControl)
                }
            #elseif !os(tvOS)
                capabilities.insert(.accessControl)
            #endif
            self.capabilities = capabilities
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
            try mapStatus(SecItemAdd(try addQuery(from: query, attributes: attributes) as CFDictionary, nil))
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
            let match = matchQuery(from: query)
            var storedProtection: CFString?
            if attributes.accessControl != nil, attributes.accessibility == nil {
                storedProtection = try self.storedProtection(matching: match)
            }
            let status = SecItemUpdate(
                match as CFDictionary,
                try updateAttributes(from: attributes, storedProtection: storedProtection) as CFDictionary
            )
            try mapStatus(status)
            SwiftyChainLoggers.backend.debug("SecItemUpdate succeeded")
        }

        package func delete(matching query: KeychainQuery) throws {
            logSecurityCall("SecItemDelete", query: query)
            do {
                try deleteEveryMatch(matchQuery(from: query))
            } catch KeychainError.operationFailed(errSecParam) where query.itemClass == .internetPassword {
                throw KeychainError.invalidArgument("The keychain rejected the internet-password deletion filters")
            }
        }

        // The macOS legacy keychain removes one matching item per SecItemDelete
        // call, even when more match. Loop until the keychain reports no more
        // matches so bulk deletes actually clear everything.
        fileprivate func deleteEveryMatch(_ attributes: [String: Any]) throws {
            let attributes = attributes as CFDictionary
            for _ in 0..<deleteSafetyCap {
                let status = SecItemDelete(attributes)
                if status == errSecItemNotFound {
                    SwiftyChainLoggers.backend.debug("SecItemDelete completed")
                    return
                }
                try mapStatus(status)
            }
            SwiftyChainLoggers.backend.fault("SecItemDelete exceeded its safety cap")
            throw KeychainError.operationFailed(errSecInternalError)
        }

        /// The dictionary `SecItemAdd` receives: the identity attributes plus every written value.
        package func addQuery(from query: KeychainQuery, attributes: KeychainAttributes) throws -> [String: Any] {
            var secAttributes = secQuery(from: query)
            secAttributes[kSecValueData as String] = attributes.data ?? Data()
            if let label = attributes.label {
                secAttributes[kSecAttrLabel as String] = label
            }
            if let comment = attributes.comment {
                secAttributes[kSecAttrComment as String] = comment
            }
            secAttributes.merge(
                try protectionAttributes(
                    accessibility: attributes.accessibility, accessControl: attributes.accessControl)
            ) { _, new in new }
            return secAttributes
        }

        /// The dictionary of changes `SecItemUpdate` receives.
        ///
        /// - Parameter storedProtection: The `kSecAttrAccessible` value the matching items
        ///   already have. An access-control policy is built with it when `attributes`
        ///   names no accessibility, so adding access control doesn't change when an
        ///   item can be read.
        package func updateAttributes(
            from attributes: KeychainAttributes, storedProtection: CFString? = nil
        ) throws -> [String: Any] {
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
            secAttributes.merge(
                try protectionAttributes(
                    protection: attributes.accessibility?.secValue ?? storedProtection,
                    accessControl: attributes.accessControl)
            ) { _, new in new }
            return secAttributes
        }

        package func protectionAttributes(
            accessibility: KeychainAccessibility?, accessControl: KeychainAccessControl?
        ) throws -> [String: Any] {
            try protectionAttributes(protection: accessibility?.secValue, accessControl: accessControl)
        }

        /// The `kSecAttrAccessible` value every item `match` selects shares, or `nil` when
        /// no item has one SwiftyChain knows.
        ///
        /// Reading an item's attributes needs authentication on macOS when the item has an
        /// access-control policy, so this probes each accessibility value with
        /// ``itemExists(matching:)`` instead, which never prompts.
        private func storedProtection(matching match: [String: Any]) throws -> CFString? {
            let present = try KeychainAccessibility.allSecValues.filter { protection in
                var probe = match
                probe[kSecAttrAccessible as String] = protection
                return try itemExists(matching: probe)
            }
            return try Self.sharedProtection(present)
        }

        /// The one protection value in `present`, or `nil` when it is empty.
        ///
        /// - Throws: ``KeychainError/invalidArgument(_:)`` when the matching items have
        ///   different values, because one access-control policy can't keep each item's own
        ///   accessibility.
        package static func sharedProtection(_ present: [CFString]) throws -> CFString? {
            guard present.count <= 1 else {
                SwiftyChainLoggers.backend.debug("Matching items have different accessibility values")
                throw KeychainError.invalidArgument(
                    "The matching items have different accessibility values; pass an accessibility with the access control"
                )
            }
            return present.first
        }

        /// Whether any item matches, without reading it and without prompting.
        ///
        /// A matching item protected by an access-control policy reports
        /// `errSecInteractionNotAllowed` instead of being read, which still shows it exists.
        private func itemExists(matching match: [String: Any]) throws -> Bool {
            var probe = match
            probe[kSecMatchLimit as String] = kSecMatchLimitOne
            #if canImport(LocalAuthentication)
                let context = LAContext()
                context.interactionNotAllowed = true
                probe[kSecUseAuthenticationContext as String] = context
            #endif
            let status = SecItemCopyMatching(probe as CFDictionary, nil)
            switch status {
            case errSecSuccess, errSecInteractionNotAllowed:
                return true
            case errSecItemNotFound:
                return false
            default:
                try mapStatus(status)
                return false
            }
        }

        private func protectionAttributes(
            protection: CFString?, accessControl: KeychainAccessControl?
        ) throws -> [String: Any] {
            if let accessControl {
                #if os(tvOS)
                    throw KeychainError.platformUnsupported("Access control is not supported on tvOS")
                #else
                    guard capabilities.contains(.accessControl) else {
                        throw KeychainError.platformUnsupported(
                            "Access control is not supported by this keychain backend or configuration")
                    }
                    let flags: SecAccessControlCreateFlags =
                        switch accessControl {
                        case .userPresence: .userPresence
                        case .biometryAny: .biometryAny
                        case .biometryCurrentSet: .biometryCurrentSet
                        case .devicePasscode: .devicePasscode
                        }
                    var error: Unmanaged<CFError>?
                    guard
                        let control = SecAccessControlCreateWithFlags(
                            nil, protection ?? KeychainAccessibility.whenUnlocked.secValue, flags, &error
                        )
                    else {
                        if let error { _ = error.takeRetainedValue() }
                        throw KeychainError.invalidArgument("The access-control policy could not be created")
                    }
                    return [kSecAttrAccessControl as String: control]
                #endif
            }
            if let protection {
                return [kSecAttrAccessible as String: protection]
            }
            return [:]
        }

        private func configuredQuery(_ attributes: [String: Any]) -> [String: Any] {
            var attributes = attributes
            #if os(macOS)
                if configuration.macOSStore == .dataProtection {
                    attributes[kSecUseDataProtectionKeychain as String] = true
                }
            #endif
            return attributes
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

            return configuredQuery(attributes)
        }
        // swiftlint:enable cyclomatic_complexity

        private func logSecurityCall(_ operation: StaticString, query: KeychainQuery) {
            SwiftyChainLoggers.backend.debug(
                "\(operation) started for itemClass=\(String(describing: query.itemClass), privacy: .public) service=\(query.service ?? "<none>", privacy: .private(mask: .hash)) account=\(query.account ?? "<none>", privacy: .private(mask: .hash)) server=\(query.server ?? "<none>", privacy: .private(mask: .hash))"
            )
        }

        package func mapStatus(_ status: OSStatus) throws {
            switch status {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                SwiftyChainLoggers.backend.debug("Security operation returned item not found")
                throw KeychainError.itemNotFound
            case errSecDuplicateItem:
                SwiftyChainLoggers.backend.debug("Security operation returned duplicate item")
                throw KeychainError.duplicateItem
            case errSecAuthFailed:
                SwiftyChainLoggers.backend.debug("Security operation returned authentication failure")
                throw KeychainError.authenticationFailed
            case errSecUserCanceled:
                SwiftyChainLoggers.backend.debug("Security operation was canceled by the user")
                throw KeychainError.userCanceled
            case errSecInteractionNotAllowed:
                SwiftyChainLoggers.backend.debug("Security operation needs interaction that isn't allowed")
                throw KeychainError.interactionNotAllowed
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
        /// The `kSecAttrAccessible` value of every case.
        package static var allSecValues: [CFString] {
            [
                KeychainAccessibility.afterFirstUnlock, .afterFirstUnlockThisDeviceOnly, .whenUnlocked,
                .whenUnlockedThisDeviceOnly, .whenPasscodeSetThisDeviceOnly,
            ].map(\.secValue)
        }

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
                // The keychain's uniqueness rule for keys includes the public-key hash, type,
                // and size, so SecItemAdd accepts a second, different key under the same tag.
                // SwiftyChain identifies a key by tag and access group, so it checks first.
                if try itemExists(matching: cryptoSecQuery(from: query)) {
                    SwiftyChainLoggers.backend.debug("SecItemAdd skipped: a key with this tag already exists")
                    throw KeychainError.duplicateItem
                }
                var attributes = cryptoSecQuery(from: query)
                attributes[kSecValueRef as String] = key
                attributes.merge(
                    try protectionAttributes(
                        accessibility: keyAttributes.accessibility, accessControl: keyAttributes.accessControl)
                ) { _, new in new }
                let status = SecItemAdd(attributes as CFDictionary, nil)
                try mapStatus(status)
            }

            package func updateCryptoKey(_ key: SecKey, query: CryptoKeyQuery, attributes: CryptoKeyAttributes) throws {
                #if os(macOS)
                    guard configuration.macOSStore == .dataProtection else {
                        throw KeychainError.invalidArgument(
                            "The macOS legacy store cannot replace cryptographic key material in place; use the data-protection store"
                        )
                    }
                #endif
                let match = cryptoSecQuery(from: query)
                guard try itemExists(matching: match) else {
                    throw KeychainError.itemNotFound
                }
                // The update only rewrites the key bytes, so it is limited to keys whose type,
                // class, and size already describe the replacement. A key of another shape
                // would end up holding bytes it can't decode. Matching on these attributes
                // never prompts, unlike reading them.
                let replacementAttributes = SecKeyCopyAttributes(key) as? [String: Any] ?? [:]
                let sameShape = match.merging(Self.cryptoKeyShape(of: replacementAttributes)) { _, new in new }
                guard try itemExists(matching: sameShape) else {
                    SwiftyChainLoggers.backend.debug("Rejected a crypto key update that changes the key's shape")
                    throw KeychainError.invalidArgument(
                        "The replacement key's type, class, or size differs from the stored key; delete the stored key first"
                    )
                }
                var error: Unmanaged<CFError>?
                guard let data = SecKeyCopyExternalRepresentation(key, &error) else {
                    if let error { _ = error.takeRetainedValue() }
                    throw KeychainError.invalidArgument("Updating a cryptographic key requires exportable key material")
                }
                var storedProtection: CFString?
                if attributes.accessControl != nil, attributes.accessibility == nil {
                    storedProtection = try self.storedProtection(matching: sameShape)
                }
                var changes = try protectionAttributes(
                    protection: attributes.accessibility?.secValue ?? storedProtection,
                    accessControl: attributes.accessControl)
                changes[kSecValueData as String] = data
                // The application label is the public-key hash of the stored material, so it
                // must follow the new key.
                if let label = replacementAttributes[kSecAttrApplicationLabel as String] {
                    changes[kSecAttrApplicationLabel as String] = label
                }
                try mapStatus(SecItemUpdate(sameShape as CFDictionary, changes as CFDictionary))
            }

            /// The type, class, and size from a key's attributes, as query attributes that
            /// select stored keys of the same shape.
            package static func cryptoKeyShape(of attributes: [String: Any]) -> [String: Any] {
                let names = [kSecAttrKeyType, kSecAttrKeyClass, kSecAttrKeySizeInBits].map { $0 as String }
                return attributes.filter { names.contains($0.key) }
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
                try deleteEveryMatch(cryptoSecQuery(from: query))
            }

            package func deleteAllCryptoKeys(accessGroup: String?) throws {
                SwiftyChainLoggers.backend.debug(
                    "SecItemDelete started for itemClass=cryptographicKey accessGroup=\(accessGroup ?? "<none>", privacy: .private(mask: .hash))"
                )
                try deleteEveryMatch(cryptoBulkDeleteQuery(accessGroup: accessGroup))
            }

            /// The dictionary a bulk delete of keys matches: the key class and, when given,
            /// the access group. Keys have no service attribute.
            package func cryptoBulkDeleteQuery(accessGroup: String?) -> [String: Any] {
                var attributes: [String: Any] = [kSecClass as String: kSecClassKey]
                if let accessGroup {
                    attributes[kSecAttrAccessGroup as String] = accessGroup
                }
                return configuredQuery(attributes)
            }

            package func cryptoSecQuery(from query: CryptoKeyQuery) -> [String: Any] {
                var attributes: [String: Any] = [
                    kSecClass as String: kSecClassKey,
                    kSecAttrApplicationTag as String: Data(query.tag.utf8),
                ]
                if let accessGroup = query.accessGroup {
                    attributes[kSecAttrAccessGroup as String] = accessGroup
                }
                return configuredQuery(attributes)
            }
        }
    #endif
#endif
