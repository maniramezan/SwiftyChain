import Foundation
import SwiftyChain
import SwiftyChainTesting
import Testing

#if canImport(SwiftyChainAppleKeychain)
    import SwiftyChainAppleKeychain
#endif

/// A backend the contract suite runs against, with the features the test host can exercise.
struct BackendFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let make: @Sendable () -> any SecureStorageBackend
    /// Synchronizable writes need an iCloud-entitled app on Apple platforms.
    let canWriteSynchronizableItems: Bool
    /// Custom access groups need a keychain-sharing entitlement on Apple platforms.
    let canUseCustomAccessGroups: Bool

    var testDescription: String { name }

    static var available: [BackendFixture] {
        var fixtures = [
            BackendFixture(
                name: "in-memory",
                make: { InMemoryStorageBackend() },
                canWriteSynchronizableItems: true,
                canUseCustomAccessGroups: true
            )
        ]
        #if canImport(SwiftyChainAppleKeychain)
            if ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_KEYCHAIN_INTEGRATION"] == "1" {
                fixtures.append(
                    BackendFixture(
                        name: "apple-keychain",
                        make: { AppleKeychainBackend() },
                        canWriteSynchronizableItems: false,
                        canUseCustomAccessGroups: false
                    )
                )
            }
        #endif
        return fixtures
    }
}

private func uniqueService() -> String {
    "dev.manman.SwiftyChain.contract.\(UUID().uuidString)"
}

@Suite("Backend contract", .serialized)
struct BackendContractTests {
    @Test(arguments: BackendFixture.available)
    func saveThenLoadRoundTrips(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = KeychainKey<String>(service: uniqueService(), account: "token")

        try await keychain.save("secret", for: key)
        let loaded = try await keychain.load(key: key)
        try await keychain.delete(key: key)

        #expect(loaded == "secret")
    }

    @Test(arguments: BackendFixture.available)
    func saveRejectsDuplicates(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = KeychainKey<String>(service: uniqueService(), account: "token")
        try await keychain.save("first", for: key)

        await #expect(throws: KeychainError.duplicateItem) {
            try await keychain.save("second", for: key)
        }
        let loaded = try await keychain.load(key: key)
        try await keychain.delete(key: key)
        #expect(loaded == "first")
    }

    @Test(arguments: BackendFixture.available)
    func missingItemsReportItemNotFound(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = KeychainKey<String>(service: uniqueService(), account: "missing")

        await #expect(throws: KeychainError.itemNotFound) {
            try await keychain.load(key: key)
        }
        await #expect(throws: KeychainError.itemNotFound) {
            try await keychain.update("value", for: key)
        }
        #expect(try await keychain.loadIfPresent(key: key) == nil)
        #expect(try await keychain.exists(key: key) == false)
    }

    @Test(arguments: BackendFixture.available)
    func deletingMissingItemSucceeds(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = KeychainKey<String>(service: uniqueService(), account: "missing")

        try await keychain.delete(key: key)
    }

    @Test(arguments: BackendFixture.available)
    func updateAndUpsertReplaceValues(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = KeychainKey<String>(service: uniqueService(), account: "token")

        try await keychain.upsert("first", for: key)
        let afterInsert = try await keychain.load(key: key)
        try await keychain.upsert("second", for: key)
        let afterUpsert = try await keychain.load(key: key)
        try await keychain.update("third", for: key)
        let afterUpdate = try await keychain.load(key: key)
        let exists = try await keychain.exists(key: key)
        try await keychain.delete(key: key)

        #expect(afterInsert == "first")
        #expect(afterUpsert == "second")
        #expect(afterUpdate == "third")
        #expect(exists)
        #expect(try await keychain.exists(key: key) == false)
    }

    @Test(arguments: BackendFixture.available)
    func binaryValuesRoundTripExactly(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = KeychainKey<Data>(service: uniqueService(), account: "blob")
        let payload = Data([0x00, 0xFF, 0x00, 0x80, 0x7F] + (0..<20_000).map { UInt8(truncatingIfNeeded: $0) })

        try await keychain.save(payload, for: key)
        let loaded = try await keychain.load(key: key)
        try await keychain.delete(key: key)

        #expect(loaded == payload)
    }

    @Test(arguments: BackendFixture.available)
    func allAccountsListsOnlyTheService(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let service = uniqueService()
        let otherService = uniqueService()
        try await keychain.save("a", for: KeychainKey<String>(service: service, account: "alice"))
        try await keychain.save("b", for: KeychainKey<String>(service: service, account: "bob"))
        try await keychain.save("c", for: KeychainKey<String>(service: otherService, account: "carol"))

        let accounts = try await keychain.allAccounts(service: service)
        let missing = try await keychain.allAccounts(service: uniqueService())
        try await keychain.deleteAll(service: service)
        try await keychain.deleteAll(service: otherService)

        #expect(Set(accounts) == ["alice", "bob"])
        #expect(missing.isEmpty)
    }

    @Test(arguments: BackendFixture.available)
    func deleteAllRemovesOnlyTheService(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let service = uniqueService()
        let otherService = uniqueService()
        let kept = KeychainKey<String>(service: otherService, account: "kept")
        try await keychain.save("a", for: KeychainKey<String>(service: service, account: "a"))
        try await keychain.save("b", for: KeychainKey<String>(service: service, account: "b"))
        try await keychain.save("kept", for: kept)

        try await keychain.deleteAll(service: service)
        let remaining = try await keychain.allAccounts(service: service)
        let keptValue = try await keychain.loadIfPresent(key: kept)
        try await keychain.deleteAll(service: otherService)

        #expect(remaining.isEmpty)
        #expect(keptValue == "kept")
    }

    @Test(arguments: BackendFixture.available.filter(\.canWriteSynchronizableItems))
    func deleteAllIncludesSynchronizableItems(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let service = uniqueService()
        try await keychain.save("local", for: KeychainKey<String>(service: service, account: "local"))
        try await keychain.save(
            "synced",
            for: KeychainKey<String>(service: service, account: "synced", isSynchronizable: true)
        )

        try await keychain.deleteAllSynchronizable(service: service)
        let afterSyncDelete = try await keychain.allAccounts(service: service)
        try await keychain.deleteAll(service: service)
        let afterDeleteAll = try await keychain.allAccounts(service: service)

        #expect(afterSyncDelete == ["local"])
        #expect(afterDeleteAll.isEmpty)
    }

    @Test(arguments: BackendFixture.available.filter(\.canUseCustomAccessGroups))
    func accessGroupsScopeLookups(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let service = uniqueService()
        let groupA = KeychainKey<String>(service: service, account: "token", accessGroup: "group.a")
        let groupB = KeychainKey<String>(service: service, account: "token", accessGroup: "group.b")
        let anyGroup = KeychainKey<String>(service: service, account: "token")
        try await keychain.save("a", for: groupA)
        try await keychain.save("b", for: groupB)

        let loadedA = try await keychain.load(key: groupA)
        let loadedB = try await keychain.load(key: groupB)
        try await keychain.delete(key: groupA)
        let afterDeleteA = try await keychain.loadIfPresent(key: groupB)
        let unscoped = try await keychain.exists(key: anyGroup)
        try await keychain.deleteAll(service: service)

        #expect(loadedA == "a")
        #expect(loadedB == "b")
        #expect(afterDeleteA == "b")
        #expect(unscoped)
    }

    @Test(arguments: BackendFixture.available)
    func internetPasswordsRoundTrip(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = InternetPasswordKey(
            server: "\(UUID().uuidString.lowercased()).example.com",
            account: "alice",
            port: 8443,
            path: "/login",
            protocol: .https,
            authenticationType: .htmlForm
        )
        let otherPort = InternetPasswordKey(
            server: key.server,
            account: "alice",
            port: 9443,
            path: "/login",
            protocol: .https,
            authenticationType: .htmlForm
        )

        try await keychain.saveInternetPassword("hunter2", for: key)
        let loaded = try await keychain.loadInternetPassword(for: key)
        await #expect(throws: KeychainError.duplicateItem) {
            try await keychain.saveInternetPassword("again", for: key)
        }
        await #expect(throws: KeychainError.itemNotFound) {
            try await keychain.loadInternetPassword(for: otherPort)
        }
        try await keychain.deleteInternetPassword(for: key)

        #expect(loaded == "hunter2")
        await #expect(throws: KeychainError.itemNotFound) {
            try await keychain.loadInternetPassword(for: key)
        }
    }
}

/// A backend that reports only the given capabilities, for testing validation.
private struct RestrictedBackend: SecureStorageBackend {
    let base: InMemoryStorageBackend
    let capabilities: SecureStorageCapabilities

    func add(_ query: KeychainQuery, data: Data) throws {
        try base.add(query, data: data)
    }

    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        try base.copyMatching(query)
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        try base.update(matching: query, to: attributes)
    }

    func delete(matching query: KeychainQuery) throws {
        try base.delete(matching: query)
    }
}

@Suite("Capability validation")
struct CapabilityValidationTests {
    private let keychain = Keychain(backend: RestrictedBackend(base: InMemoryStorageBackend(), capabilities: []))

    @Test
    func synchronizableItemsAreRejected() async throws {
        let key = KeychainKey<String>(service: "tests.capabilities", account: "a", isSynchronizable: true)

        await #expect(
            throws: KeychainError.platformUnsupported(
                "Synchronizable items are not supported by this keychain backend"
            )
        ) {
            try await keychain.save("value", for: key)
        }
        await #expect(
            throws: KeychainError.platformUnsupported(
                "Synchronizable items are not supported by this keychain backend"
            )
        ) {
            try await keychain.deleteAllSynchronizable(service: "tests.capabilities")
        }
    }

    @Test
    func accessGroupsAreRejected() async throws {
        let key = KeychainKey<String>(service: "tests.capabilities", account: "a", accessGroup: "group.a")

        await #expect(
            throws: KeychainError.platformUnsupported(
                "Access groups are not supported by this keychain backend"
            )
        ) {
            try await keychain.save("value", for: key)
        }
    }

    @Test
    func internetPasswordsAreRejected() async throws {
        let key = InternetPasswordKey(server: "example.com", account: "alice")

        await #expect(
            throws: KeychainError.platformUnsupported(
                "Internet passwords are not supported by this keychain backend"
            )
        ) {
            try await keychain.saveInternetPassword("pw", for: key)
        }
    }

    @Test
    func supportedOperationsStillWork() async throws {
        let key = KeychainKey<String>(service: "tests.capabilities", account: "a")

        try await keychain.save("value", for: key)
        try await keychain.deleteAll(service: "tests.capabilities")

        #expect(try await keychain.loadIfPresent(key: key) == nil)
    }

    @Test
    func keychainStorageValidatesThroughTheAdapter() {
        let storage = KeychainStorage<String>(
            "a",
            service: "tests.capabilities",
            backend: SecureStorageKeychainBackend(
                RestrictedBackend(base: InMemoryStorageBackend(), capabilities: [])
            ),
            isSynchronizable: true
        )

        storage.wrappedValue = "value"

        #expect(
            storage.projectedValue
                == .platformUnsupported("Synchronizable items are not supported by this keychain backend")
        )
    }
}

@Suite("Unsupported platform")
struct UnsupportedPlatformBackendTests {
    private let keychain = Keychain(backend: UnsupportedPlatformBackend())
    private let unsupported = KeychainError.platformUnsupported("No secure storage is available on this platform")

    @Test
    func everyOperationFailsClosed() async throws {
        let key = KeychainKey<String>(service: "tests.unsupported", account: "a")

        await #expect(throws: unsupported) { try await keychain.save("value", for: key) }
        await #expect(throws: unsupported) { try await keychain.load(key: key) }
        await #expect(throws: unsupported) { try await keychain.update("value", for: key) }
        await #expect(throws: unsupported) { try await keychain.delete(key: key) }
        await #expect(throws: unsupported) { try await keychain.exists(key: key) }
        await #expect(throws: unsupported) { try await keychain.allAccounts(service: "tests.unsupported") }
    }
}
