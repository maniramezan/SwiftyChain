import Foundation
import Testing

@testable import SwiftyChain

@Test
func directUpdateReplacesValue() async throws {
    let keychain = Keychain(backend: MockKeychainBackend())
    let key = KeychainKey<String>(service: "tests", account: "token")

    try await keychain.save("one", for: key)
    try await keychain.update("two", for: key)

    #expect(try await keychain.load(key: key) == "two")
}

@Test
func directUpdateOnMissingItemThrows() async throws {
    let keychain = Keychain(backend: MockKeychainBackend())
    let key = KeychainKey<String>(service: "tests", account: "missing")

    await #expect(throws: KeychainError.itemNotFound) {
        try await keychain.update("two", for: key)
    }
}

@Test
func updateMatchesByIdentityIgnoringAttributes() async throws {
    let keychain = Keychain(backend: MockKeychainBackend())
    let labeled = KeychainKey<String>(
        service: "tests",
        account: "token",
        label: "old label",
        comment: "old comment"
    )
    let relabeled = KeychainKey<String>(
        service: "tests",
        account: "token",
        accessibility: .afterFirstUnlock,
        label: "new label",
        comment: "new comment"
    )

    try await keychain.save("v1", for: labeled)
    try await keychain.update("v2", for: relabeled)

    #expect(try await keychain.load(key: relabeled) == "v2")
    #expect(try await keychain.load(key: labeled) == "v2")
}

@Test
func upsertCreatesAndThenReplaces() async throws {
    let keychain = Keychain(backend: MockKeychainBackend())
    let key = KeychainKey<String>(service: "tests", account: "token")

    try await keychain.upsert("first", for: key)
    #expect(try await keychain.load(key: key) == "first")

    try await keychain.upsert("second", for: key)
    #expect(try await keychain.load(key: key) == "second")
}

@Test
func deleteAllSynchronizableLeavesLocalItems() async throws {
    let keychain = Keychain(backend: MockKeychainBackend())
    let localKey = KeychainKey<String>(service: "tests", account: "local")
    let syncKey = KeychainKey<String>(
        service: "tests",
        account: "synced",
        isSynchronizable: true
    )

    try await keychain.save("local", for: localKey)
    try await keychain.save("synced", for: syncKey)

    try await keychain.deleteAllSynchronizable(service: "tests")

    #expect(try await keychain.load(key: localKey) == "local")
    #expect(try await keychain.loadIfPresent(key: syncKey) == nil)
}

@Test
func deleteAllItemsWithCustomQueryRespectsFilters() async throws {
    let keychain = Keychain(backend: MockKeychainBackend())
    try await keychain.save(
        "local",
        for: KeychainKey<String>(service: "tests", account: "a")
    )
    try await keychain.save(
        "synced",
        for: KeychainKey<String>(service: "tests", account: "b", isSynchronizable: true)
    )

    try await keychain.deleteAllItems(
        matching: KeychainDeleteQuery(
            service: "tests",
            includeSynchronizable: false,
            onlySynchronizable: false
        )
    )

    #expect(Set(try await keychain.allAccounts(service: "tests")) == ["b"])
}
