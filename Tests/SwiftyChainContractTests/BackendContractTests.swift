import Foundation
import SwiftyChain
import SwiftyChainTesting
import Testing

#if canImport(Security)
    import Security
    import SwiftyChainAppleKeychain
#elseif os(Linux)
    import SwiftyChainSecretService
#endif

/// A backend the contract suite runs against, with the features the test host can exercise.
struct BackendFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let make: @Sendable () -> any KeychainBackend
    /// Synchronizable writes need an iCloud-entitled app on Apple platforms.
    let canWriteSynchronizableItems: Bool
    /// Custom access groups need a keychain-sharing entitlement on Apple platforms.
    let canUseCustomAccessGroups: Bool
    /// Whether the backend's storage belongs to the test alone, so a delete that names no
    /// service can't remove the developer's own keychain items.
    var isIsolated = false

    var testDescription: String { name }

    static var available: [BackendFixture] {
        var fixtures = [
            BackendFixture(
                name: "in-memory",
                make: { InMemoryKeychainBackend() },
                canWriteSynchronizableItems: true,
                canUseCustomAccessGroups: true,
                isIsolated: true
            ),
            BackendFixture(
                name: "in-memory emulating Linux",
                make: { InMemoryKeychainBackend(capabilities: EmulatedKeychainPlatform.linux.capabilities) },
                canWriteSynchronizableItems: false,
                canUseCustomAccessGroups: true,
                isIsolated: true
            ),
        ]
        #if canImport(Security)
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
        #elseif os(Linux)
            if ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_SECRET_SERVICE_INTEGRATION"] == "1" {
                fixtures.append(
                    BackendFixture(
                        name: "secret-service",
                        make: { SecretServiceBackend() },
                        canWriteSynchronizableItems: false,
                        canUseCustomAccessGroups: true
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

/// Runs `body`, then removes every item it may have stored, even when `body` throws,
/// so a failing run never leaves items behind in the developer's real keychain.
private func withCleanup(
    _ keychain: Keychain,
    services: [String] = [],
    internetPasswords: [InternetPasswordKey] = [],
    _ body: () async throws -> Void
) async throws {
    do {
        try await body()
    } catch {
        await cleanUp(keychain, services: services, internetPasswords: internetPasswords)
        throw error
    }
    await cleanUp(keychain, services: services, internetPasswords: internetPasswords)
}

private func cleanUp(_ keychain: Keychain, services: [String], internetPasswords: [InternetPasswordKey]) async {
    for service in services {
        do {
            try await keychain.deleteAll(service: service)
        } catch {
            Issue.record("Could not clean up items for a contract-test service: \(error)")
        }
    }
    for key in internetPasswords {
        do {
            try await keychain.deleteInternetPassword(for: key)
        } catch {
            Issue.record("Could not clean up a contract-test internet password: \(error)")
        }
    }
}

@Suite("Backend contract", .serialized)
struct BackendContractTests {
    @Test(arguments: BackendFixture.available)
    func saveThenLoadRoundTrips(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = KeychainKey<String>(service: uniqueService(), account: "token")

        try await withCleanup(keychain, services: [key.service]) {
            try await keychain.save("secret", for: key)
            let loaded = try await keychain.load(key: key)

            #expect(loaded == "secret")
        }
    }

    @Test(arguments: BackendFixture.available)
    func saveRejectsDuplicates(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = KeychainKey<String>(service: uniqueService(), account: "token")

        try await withCleanup(keychain, services: [key.service]) {
            try await keychain.save("first", for: key)
            await #expect(throws: KeychainError.duplicateItem) {
                try await keychain.save("second", for: key)
            }
            let loaded = try await keychain.load(key: key)

            #expect(loaded == "first")
        }
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

        try await withCleanup(keychain, services: [key.service]) {
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
    }

    @Test(arguments: BackendFixture.available)
    func binaryValuesRoundTripExactly(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = KeychainKey<Data>(service: uniqueService(), account: "blob")
        let payload = Data([0x00, 0xFF, 0x00, 0x80, 0x7F] + (0..<20_000).map { UInt8(truncatingIfNeeded: $0) })

        try await withCleanup(keychain, services: [key.service]) {
            try await keychain.save(payload, for: key)
            let loaded = try await keychain.load(key: key)

            #expect(loaded == payload)
        }
    }

    @Test(arguments: BackendFixture.available)
    func allAccountsListsOnlyTheService(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let service = uniqueService()
        let otherService = uniqueService()

        try await withCleanup(keychain, services: [service, otherService]) {
            try await keychain.save("a", for: KeychainKey<String>(service: service, account: "alice"))
            try await keychain.save("b", for: KeychainKey<String>(service: service, account: "bob"))
            try await keychain.save("c", for: KeychainKey<String>(service: otherService, account: "carol"))

            let accounts = try await keychain.allAccounts(service: service)
            let missing = try await keychain.allAccounts(service: uniqueService())

            #expect(Set(accounts) == ["alice", "bob"])
            #expect(missing.isEmpty)
        }
    }

    @Test(arguments: BackendFixture.available)
    func deleteAllRemovesOnlyTheService(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let service = uniqueService()
        let otherService = uniqueService()
        let kept = KeychainKey<String>(service: otherService, account: "kept")

        try await withCleanup(keychain, services: [service, otherService]) {
            try await keychain.save("a", for: KeychainKey<String>(service: service, account: "a"))
            try await keychain.save("b", for: KeychainKey<String>(service: service, account: "b"))
            try await keychain.save("kept", for: kept)

            try await keychain.deleteAll(service: service)
            let remaining = try await keychain.allAccounts(service: service)
            let keptValue = try await keychain.loadIfPresent(key: kept)

            #expect(remaining.isEmpty)
            #expect(keptValue == "kept")
        }
    }

    @Test(arguments: BackendFixture.available.filter(\.canWriteSynchronizableItems))
    func deleteAllIncludesSynchronizableItems(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let service = uniqueService()

        try await withCleanup(keychain, services: [service]) {
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
    }

    @Test(arguments: BackendFixture.available.filter(\.canUseCustomAccessGroups))
    func accessGroupsScopeLookups(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let service = uniqueService()
        let groupA = KeychainKey<String>(service: service, account: "token", accessGroup: "group.a")
        let groupB = KeychainKey<String>(service: service, account: "token", accessGroup: "group.b")
        let anyGroup = KeychainKey<String>(service: service, account: "token")

        try await withCleanup(keychain, services: [service]) {
            try await keychain.save("a", for: groupA)
            try await keychain.save("b", for: groupB)

            let loadedA = try await keychain.load(key: groupA)
            let loadedB = try await keychain.load(key: groupB)
            try await keychain.delete(key: groupA)
            let afterDeleteA = try await keychain.loadIfPresent(key: groupB)
            let unscoped = try await keychain.exists(key: anyGroup)

            #expect(loadedA == "a")
            #expect(loadedB == "b")
            #expect(afterDeleteA == "b")
            #expect(unscoped)
        }
    }

    #if os(Linux) && Cryptography
        @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_SECRET_SERVICE_INTEGRATION"] == "1"))
        func cryptoDeletionCannotSelectLinuxPasswords() async throws {
            let keychain = Keychain()
            let key = KeychainKey<String>(service: uniqueService(), account: "kept")

            try await withCleanup(keychain, services: [key.service]) {
                try await keychain.save("secret", for: key)

                await #expect(
                    throws: KeychainError.platformUnsupported(
                        "Cryptographic keys are not supported by this keychain backend"
                    )
                ) {
                    try await keychain.deleteAllItems(matching: KeychainDeleteQuery(itemClass: .cryptographicKey))
                }

                let loaded = try await keychain.load(key: key)
                #expect(loaded == "secret")
            }
        }
    #endif

    @Test(arguments: BackendFixture.available)
    func unscopedDeletesFollowTheBackendsCapabilities(_ fixture: BackendFixture) async throws {
        let backend = fixture.make()
        let keychain = Keychain(backend: backend)
        let kept = KeychainKey<String>(service: uniqueService(), account: "kept")
        let unscopedQueries = [
            KeychainDeleteQuery(),
            KeychainDeleteQuery(service: ""),
            KeychainDeleteQuery(itemClass: .internetPassword),
        ]

        try await withCleanup(keychain, services: [kept.service]) {
            try await keychain.save("kept", for: kept)

            if backend.capabilities.contains(.unscopedBulkDelete) {
                guard fixture.isIsolated else { return }
                for query in unscopedQueries {
                    try await keychain.deleteAllItems(matching: query)
                }
                #expect(try await keychain.loadIfPresent(key: kept) == nil)
            } else {
                for query in unscopedQueries {
                    await #expect(
                        throws: KeychainError.platformUnsupported(
                            "Deleting without a service, server, or access group is not supported by this keychain backend"
                        )
                    ) {
                        try await keychain.deleteAllItems(matching: query)
                    }
                }
                #expect(try await keychain.load(key: kept) == "kept")
            }
        }
    }

    @Test(arguments: BackendFixture.available)
    func internetPasswordBulkDeletesHonorSynchronizableFilters(_ fixture: BackendFixture) async throws {
        let keychain = Keychain(backend: fixture.make())
        let key = InternetPasswordKey(server: "\(UUID().uuidString.lowercased()).example.com", account: "alice")

        try await withCleanup(keychain, internetPasswords: [key]) {
            try await keychain.saveInternetPassword("local", for: key)

            if fixture.canWriteSynchronizableItems {
                try await keychain.deleteAllItems(
                    matching: KeychainDeleteQuery(
                        service: key.server, onlySynchronizable: true, itemClass: .internetPassword)
                )
                #expect(try await keychain.loadInternetPassword(for: key) == "local")
            }

            try await keychain.deleteAllItems(
                matching: KeychainDeleteQuery(
                    service: key.server,
                    includeSynchronizable: false,
                    itemClass: .internetPassword
                )
            )
            await #expect(throws: KeychainError.itemNotFound) {
                try await keychain.loadInternetPassword(for: key)
            }
        }
    }

    @Test(arguments: BackendFixture.available)
    func synchronizableItemsCantBeThisDeviceOnly(_ fixture: BackendFixture) async throws {
        let backend = fixture.make()
        let keychain = Keychain(backend: backend)
        let key = KeychainKey<String>(
            service: uniqueService(),
            account: "token",
            accessibility: .whenUnlockedThisDeviceOnly,
            isSynchronizable: true
        )

        try await withCleanup(keychain, services: [key.service]) {
            await #expect(throws: KeychainError.self) {
                try await keychain.save("value", for: key)
            }
            if backend.capabilities.contains(.synchronizable) {
                await #expect(
                    throws: KeychainError.invalidArgument(
                        "A synchronizable item can't use a ThisDeviceOnly accessibility")
                ) {
                    try await keychain.upsert("value", for: key)
                }
            }
        }
    }

    #if Cryptography && canImport(Security)
        @Test(arguments: BackendFixture.available)
        func cryptoKeyBulkDeletesUseTheCryptoBackend(_ fixture: BackendFixture) async throws {
            let backend = fixture.make()
            let keychain = Keychain(backend: backend)
            let serviceQuery = KeychainDeleteQuery(service: "com.example", itemClass: .cryptographicKey)

            guard backend.capabilities.contains(.cryptoKeys) else {
                await #expect(
                    throws: KeychainError.platformUnsupported(
                        "Cryptographic keys are not supported by this keychain backend")
                ) {
                    try await keychain.deleteAllItems(matching: KeychainDeleteQuery(itemClass: .cryptographicKey))
                }
                return
            }
            await #expect(
                throws: KeychainError.invalidArgument(
                    "Cryptographic keys have no service. Delete them by access group, or pass no service"
                )
            ) {
                try await keychain.deleteAllItems(matching: serviceQuery)
            }

            // An unscoped delete would reach the developer's own keys in a real keychain.
            guard fixture.isIsolated else { return }
            let keyRef = CryptoKeyReference<StoredSecKey>(tag: "tests.contract.crypto.\(UUID().uuidString)")
            let attributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String: 256,
            ]
            let secKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
            try await keychain.saveCryptoKey(StoredSecKey(secKey), for: keyRef)

            try await keychain.deleteAllItems(matching: KeychainDeleteQuery(itemClass: .cryptographicKey))

            await #expect(throws: KeychainError.itemNotFound) {
                _ = try await keychain.loadCryptoKey(keyRef: keyRef)
            }
        }
    #endif

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

        try await withCleanup(keychain, internetPasswords: [key]) {
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
}

@Suite("Capability validation")
struct CapabilityValidationTests {
    private let keychain = Keychain(backend: InMemoryKeychainBackend(capabilities: []))

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

    #if Cryptography
        @Test
        func unsupportedCryptoDeletionPreservesPasswords() async throws {
            let key = KeychainKey<String>(service: "tests.capabilities", account: "kept")
            try await keychain.save("secret", for: key)

            await #expect(
                throws: KeychainError.platformUnsupported(
                    "Cryptographic keys are not supported by this keychain backend"
                )
            ) {
                try await keychain.deleteAllItems(matching: KeychainDeleteQuery(itemClass: .cryptographicKey))
            }

            #expect(try await keychain.load(key: key) == "secret")
        }
    #endif

    @Test
    func supportedOperationsStillWork() async throws {
        let key = KeychainKey<String>(service: "tests.capabilities", account: "a")

        try await keychain.save("value", for: key)
        try await keychain.deleteAll(service: "tests.capabilities")

        #expect(try await keychain.loadIfPresent(key: key) == nil)
    }

    @Test
    func keychainStorageValidatesCapabilities() {
        let storage = KeychainStorage<String>(
            "a",
            service: "tests.capabilities",
            backend: InMemoryKeychainBackend(capabilities: []),
            isSynchronizable: true
        )

        storage.wrappedValue = "value"

        #expect(
            storage.projectedValue
                == .platformUnsupported("Synchronizable items are not supported by this keychain backend")
        )
    }
}

@Suite("Delete scoping")
struct DeleteScopingTests {
    @Test(
        arguments: [
            KeychainQuery(itemClass: .genericPassword, service: "com.example"),
            KeychainQuery(itemClass: .genericPassword, accessGroup: "group.a"),
            KeychainQuery(itemClass: .genericPassword, service: "", account: "token"),
            KeychainQuery(itemClass: .internetPassword, server: "example.com"),
            KeychainQuery(itemClass: .internetPassword, account: "alice", server: ""),
        ]
    )
    func deletesNamingOneAppsItemsAreScoped(_ query: KeychainQuery) {
        #expect(KeychainQueryValidator.isScoped(query))
    }

    @Test(
        arguments: [
            KeychainQuery(itemClass: .genericPassword),
            KeychainQuery(itemClass: .genericPassword, service: ""),
            KeychainQuery(itemClass: .genericPassword, account: "token"),
            KeychainQuery(itemClass: .genericPassword, accessGroup: ""),
            KeychainQuery(itemClass: .genericPassword, server: "example.com"),
            KeychainQuery(itemClass: .internetPassword, service: "com.example"),
            KeychainQuery(itemClass: .internetPassword, account: "alice", port: 443),
        ]
    )
    func deletesThatWouldMatchOtherAppsItemsAreNotScoped(_ query: KeychainQuery) {
        #expect(!KeychainQueryValidator.isScoped(query))
    }

    @Test
    func onlyDeletesAreCheckedForScope() throws {
        let unscoped = KeychainQuery(itemClass: .genericPassword)

        try KeychainQueryValidator.validate(unscoped, for: .read, against: [])
        #expect(throws: KeychainError.self) {
            try KeychainQueryValidator.validate(unscoped, for: .delete, against: [])
        }
        try KeychainQueryValidator.validate(unscoped, for: .delete, against: .unscopedBulkDelete)
    }

    @Test
    func linuxEmulationRejectsLinuxRestrictions() async throws {
        let keychain = InMemoryKeychain(emulating: .linux)
        let synced = KeychainKey<String>(service: "tests.emulation", account: "a", isSynchronizable: true)

        await #expect(
            throws: KeychainError.platformUnsupported("Synchronizable items are not supported by this keychain backend")
        ) {
            try await keychain.save("value", for: synced)
        }
        await #expect(throws: KeychainError.self) {
            try await keychain.deleteAllItems(matching: KeychainDeleteQuery())
        }
        try await keychain.save("value", for: KeychainKey<String>(service: "tests.emulation", account: "b"))
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
