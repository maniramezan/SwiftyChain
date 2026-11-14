#if canImport(Security)
    import Foundation
    import Security
    import SwiftyChain
    import SwiftyChainAppleKeychain
    import Testing

    #if os(macOS)
        @Test(arguments: [KeychainConfiguration.MacOSStore.legacy, .dataProtection])
        func macOSStoreFlagReachesEveryQuery(_ store: KeychainConfiguration.MacOSStore) {
            let backend = AppleKeychainBackend(configuration: .init(macOSStore: store))
            let identity = KeychainQuery(service: "tests.store", account: "token")
            let add = backend.addQuery(from: identity, attributes: .init())
            let match = backend.matchQuery(from: identity)
            #expect((add[kSecUseDataProtectionKeychain as String] as? Bool ?? false) == (store == .dataProtection))
            #expect((match[kSecUseDataProtectionKeychain as String] as? Bool ?? false) == (store == .dataProtection))
            #if Cryptography
                let bulk = backend.cryptoBulkDeleteQuery(accessGroup: nil)
                let crypto = backend.cryptoSecQuery(from: .init(tag: "tests.store"))
                #expect((bulk[kSecUseDataProtectionKeychain as String] as? Bool ?? false) == (store == .dataProtection))
                #expect(
                    (crypto[kSecUseDataProtectionKeychain as String] as? Bool ?? false) == (store == .dataProtection))
            #endif
        }
    #endif

    @Test
    func matchQueryIncludesSynchronizableItemsWhenUnset() throws {
        let query = AppleKeychainBackend().matchQuery(
            from: KeychainQuery(itemClass: .genericPassword, service: "tests.match")
        )
        let value = try #require(query[kSecAttrSynchronizable as String] as? String)
        #expect(value == kSecAttrSynchronizableAny as String)
    }

    @Test(arguments: [true, false])
    func matchQueryKeepsExplicitSynchronizableValue(isSynchronizable: Bool) throws {
        let query = AppleKeychainBackend().matchQuery(
            from: KeychainQuery(
                itemClass: .genericPassword,
                service: "tests.match",
                isSynchronizable: isSynchronizable
            )
        )
        let value = try #require(query[kSecAttrSynchronizable as String] as? Bool)
        #expect(value == isSynchronizable)
    }

    #if Cryptography
        @Test
        func cryptoBulkDeleteMatchesKeysByAccessGroupOnly() throws {
            let backend = AppleKeychainBackend()
            let scoped = backend.cryptoBulkDeleteQuery(accessGroup: "group.a")
            let unscoped = backend.cryptoBulkDeleteQuery(accessGroup: nil)

            #expect(scoped[kSecAttrService as String] == nil)
            #expect(scoped[kSecAttrAccessGroup as String] as? String == "group.a")
            #expect(unscoped.count == 1)
            #expect(try #require(unscoped[kSecClass as String] as? String) == kSecClassKey as String)
        }
    #endif

    @Test
    func addQueryWritesValuesAlongsideIdentity() throws {
        let query = AppleKeychainBackend().addQuery(
            from: KeychainQuery(itemClass: .genericPassword, service: "tests.add", account: "a"),
            attributes: KeychainAttributes(
                data: Data("secret".utf8),
                label: "Label",
                comment: "Comment",
                accessibility: .afterFirstUnlock
            )
        )

        #expect(query[kSecValueData as String] as? Data == Data("secret".utf8))
        #expect(query[kSecAttrLabel as String] as? String == "Label")
        #expect(query[kSecAttrComment as String] as? String == "Comment")
        #expect(
            try #require(query[kSecAttrAccessible as String] as? String)
                == kSecAttrAccessibleAfterFirstUnlock as String
        )
    }

    @Test
    func updateLeavesUnsetValuesUntouched() {
        let changes = AppleKeychainBackend().updateAttributes(from: KeychainAttributes(data: Data("new".utf8)))

        #expect(changes.count == 1)
        #expect(changes[kSecValueData as String] as? Data == Data("new".utf8))
    }

    @Test(
        arguments: [
            (errSecItemNotFound, KeychainError.itemNotFound),
            (errSecDuplicateItem, .duplicateItem),
            (errSecAuthFailed, .authenticationFailed),
            (errSecUserCanceled, .userCanceled),
            (errSecInteractionNotAllowed, .interactionNotAllowed),
            (errSecMissingEntitlement, .accessGroupDenied),
            (errSecParam, .operationFailed(errSecParam)),
        ]
    )
    func statusesMapToKeychainErrors(_ status: OSStatus, _ expected: KeychainError) {
        #expect(throws: expected) { try AppleKeychainBackend().mapStatus(status) }
    }

    @Test
    func keychainAccessibilitySecValuesAreDistinctForRepresentativeCases() {
        #expect(KeychainAccessibility.afterFirstUnlock.secValue as String != "")
        #expect(KeychainAccessibility.afterFirstUnlock.secValue != KeychainAccessibility.whenUnlocked.secValue)
        #expect(
            KeychainAccessibility.whenUnlockedThisDeviceOnly.secValue
                != KeychainAccessibility.whenPasscodeSetThisDeviceOnly.secValue
        )
    }
#endif
