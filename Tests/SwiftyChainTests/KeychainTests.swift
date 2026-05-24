import SwiftyChainTesting
import Testing

@testable import SwiftyChain

@Test
func saveLoadUpdateAndDelete() async throws {
    let keychain = InMemoryKeychain()
    let key = KeychainKey<String>(service: "tests", account: "token")

    try await keychain.save("one", for: key)
    #expect(try await keychain.load(key: key) == "one")

    try await keychain.upsert("two", for: key)
    #expect(try await keychain.load(key: key) == "two")
    #expect(try await keychain.exists(key: key))

    try await keychain.delete(key: key)
    #expect(try await keychain.loadIfPresent(key: key) == nil)
}

@Test
func allAccountsAndBulkDelete() async throws {
    let keychain = InMemoryKeychain()
    try await keychain.save("a", for: KeychainKey<String>(service: "tests", account: "a"))
    try await keychain.save("b", for: KeychainKey<String>(service: "tests", account: "b"))

    #expect(Set(try await keychain.allAccounts(service: "tests")) == ["a", "b"])

    try await keychain.deleteAll(service: "tests")
    #expect(try await keychain.allAccounts(service: "tests").isEmpty)
}

@Test
func keychainKeyGenericPasswordBuilderSetsFields() {
    let key = KeychainKey<String>.genericPassword(
        service: "tests.builder",
        account: "token",
        accessGroup: "group.tests",
        accessibility: .afterFirstUnlock,
        isSynchronizable: true
    )

    #expect(key.service == "tests.builder")
    #expect(key.account == "token")
    #expect(key.accessGroup == "group.tests")
    #expect(key.accessibility == .afterFirstUnlock)
    #expect(key.isSynchronizable)
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
