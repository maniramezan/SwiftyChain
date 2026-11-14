import Foundation
import SwiftyChainTesting
import Synchronization
import Testing

@testable import SwiftyChain

private struct AlwaysFailingBackend: KeychainBackend {
    let capabilities: KeychainBackendCapabilities = .all

    let error: KeychainError

    func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {
        throw error
    }

    func data(matching query: KeychainQuery) throws -> Data {
        throw error
    }

    func contains(matching query: KeychainQuery) throws -> Bool {
        throw error
    }

    func accounts(matching query: KeychainQuery) throws -> [String] {
        throw error
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        throw error
    }

    func delete(matching query: KeychainQuery) throws {
        throw error
    }
}

private final class QueryRecordingBackend: KeychainBackend, Sendable {
    let capabilities: KeychainBackendCapabilities = .all

    private let queries = Mutex<[KeychainQuery]>([])

    func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {}

    func data(matching query: KeychainQuery) throws -> Data {
        Data()
    }

    func contains(matching query: KeychainQuery) throws -> Bool {
        false
    }

    func accounts(matching query: KeychainQuery) throws -> [String] {
        []
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {}

    func delete(matching query: KeychainQuery) throws {
        queries.withLock { $0.append(query) }
    }

    func lastDeleteQuery() -> KeychainQuery? {
        queries.withLock { $0.last }
    }
}

@Test
func keychainActorGenericOperationsUseRealKeychainPaths() async throws {
    let keychain = Keychain(backend: InMemoryKeychainBackend())
    let localKey = KeychainKey<String>(
        service: "tests.actor",
        account: "token",
        label: "original",
        comment: "first"
    )
    let syncKey = KeychainKey<String>(
        service: "tests.actor",
        account: "synced",
        isSynchronizable: true
    )
    let extraKey = KeychainKey<String>(service: "tests.actor", account: "extra")

    #expect(try await keychain.exists(key: localKey) == false)
    #expect(try await keychain.loadIfPresent(key: localKey) == nil)

    try await keychain.save("one", for: localKey)
    try await keychain.save("sync", for: syncKey)
    try await keychain.save("extra", for: extraKey)

    #expect(try await keychain.load(key: localKey) == "one")
    #expect(try await keychain.exists(key: localKey))

    let relabeledKey = KeychainKey<String>(
        service: "tests.actor",
        account: "token",
        accessibility: .afterFirstUnlock,
        label: "updated",
        comment: "second"
    )
    try await keychain.update("two", for: relabeledKey)
    #expect(try await keychain.load(key: localKey) == "two")

    try await keychain.upsert("three", for: relabeledKey)
    #expect(try await keychain.load(key: localKey) == "three")

    #expect(Set(try await keychain.allAccounts(service: "tests.actor")) == ["token", "synced", "extra"])

    try await keychain.deleteAllSynchronizable(service: "tests.actor")
    #expect(try await keychain.loadIfPresent(key: syncKey) == nil)
    #expect(try await keychain.load(key: localKey) == "three")

    try await keychain.delete(key: extraKey)
    #expect(try await keychain.exists(key: extraKey) == false)

    try await keychain.deleteAll(service: "tests.actor")
    #expect(try await keychain.allAccounts(service: "tests.actor").isEmpty)
}

@Test
func keychainActorInternetPasswordOperationsUseRealKeychainPaths() async throws {
    let keychain = Keychain(backend: InMemoryKeychainBackend())
    let primary = InternetPasswordKey(
        server: "api.example.com",
        account: "alice",
        protocol: .https,
        authenticationType: .httpBasic
    )
    let secondary = InternetPasswordKey(
        server: "api.example.com",
        account: "bob",
        protocol: .https
    )

    try await keychain.saveInternetPassword("secret-1", for: primary)
    try await keychain.saveInternetPassword("secret-2", for: secondary)

    #expect(try await keychain.loadInternetPassword(for: primary) == "secret-1")

    try await keychain.deleteInternetPassword(for: primary)
    await #expect(throws: KeychainError.itemNotFound) {
        try await keychain.loadInternetPassword(for: primary)
    }

    try await keychain.deleteAllItems(
        matching: KeychainDeleteQuery(service: "api.example.com", itemClass: .internetPassword)
    )

    await #expect(throws: KeychainError.itemNotFound) {
        try await keychain.loadInternetPassword(for: secondary)
    }
}

@Test(
    arguments: [
        (KeychainDeleteQuery(service: "api.example.com", itemClass: .internetPassword), nil),
        (KeychainDeleteQuery(service: "api.example.com", onlySynchronizable: true, itemClass: .internetPassword), true),
        (
            KeychainDeleteQuery(service: "api.example.com", includeSynchronizable: false, itemClass: .internetPassword),
            false
        ),
    ] as [(KeychainDeleteQuery, Bool?)]
)
func internetPasswordBulkDeleteHonorsSynchronizableFilters(query: KeychainDeleteQuery, expected: Bool?) async throws {
    let backend = QueryRecordingBackend()
    let keychain = Keychain(backend: backend)

    try await keychain.deleteAllItems(matching: query)

    let recorded = backend.lastDeleteQuery()
    #expect(recorded?.itemClass == .internetPassword)
    #expect(recorded?.server == "api.example.com")
    #expect(recorded?.service == nil)
    #expect(recorded?.isSynchronizable == expected)
}

@Test
func keychainActorPropagatesBackendFailures() async throws {
    let keychain = Keychain(backend: AlwaysFailingBackend(error: .unexpectedData))
    let key = KeychainKey<String>(service: "tests.actor.failures", account: "token")
    let internetKey = InternetPasswordKey(server: "failures.example.com", account: "alice")

    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.save("value", for: key)
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.load(key: key)
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.update("value", for: key)
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.delete(key: key)
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.exists(key: key)
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.deleteAll(service: "tests.actor.failures")
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.saveInternetPassword("secret", for: internetKey)
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.loadInternetPassword(for: internetKey)
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.deleteInternetPassword(for: internetKey)
    }
}

#if Observation
    @Test
    func keychainActorObservationStreamReceivesEvents() async throws {
        let keychain = Keychain(backend: InMemoryKeychainBackend())
        let key = KeychainKey<String>(service: "tests.actor.observe", account: "token")
        let stream = await keychain.observeKeychainChanges(service: "tests.actor.observe")

        async let receivedKinds: [KeychainChangeEvent.Kind] = {
            var iterator = stream.makeAsyncIterator()
            var kinds: [KeychainChangeEvent.Kind] = []
            for _ in 0..<4 {
                guard let event = await iterator.next() else { break }
                kinds.append(event.kind)
            }
            return kinds
        }()

        try await keychain.save("one", for: key)
        try await keychain.update("two", for: key)
        try await keychain.delete(key: key)
        try await keychain.deleteAll(service: "tests.actor.observe")

        #expect(await receivedKinds == [.saved, .updated, .deleted, .bulkDeleted])
    }
#endif
