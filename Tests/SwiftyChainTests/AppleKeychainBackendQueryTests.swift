#if canImport(SwiftyChainAppleKeychain)
    import Foundation
    import Security
    import SwiftyChain
    import SwiftyChainAppleKeychain
    import Testing

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
