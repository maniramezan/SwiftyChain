import Foundation
import Testing

@testable import SwiftyChain

private final class TestSecureStorageBackend: SecureStorageBackend, @unchecked Sendable {
    private struct GenericIdentity: Hashable {
        let service: String?
        let account: String?
        let accessGroup: String?
        let isSynchronizable: Bool?
    }

    private struct InternetIdentity: Hashable {
        let server: String?
        let account: String?
        let accessGroup: String?
        let port: Int?
        let path: String?
        let internetProtocol: InternetProtocol?
        let authenticationType: AuthenticationType?
    }

    private struct GenericRecord {
        var data: Data
        var label: String?
        var comment: String?
        var accessibility: KeychainAccessibility?
    }

    private struct InternetRecord {
        var data: Data
        var accessibility: KeychainAccessibility?
    }

    private let lock = NSLock()
    private var genericPasswords: [GenericIdentity: GenericRecord] = [:]
    private var internetPasswords: [InternetIdentity: InternetRecord] = [:]

    func add(_ query: KeychainQuery, data: Data) throws {
        try withLock {
            switch query.itemClass {
            case .genericPassword:
                let identity = genericIdentity(for: query)
                guard genericPasswords[identity] == nil else {
                    throw KeychainError.duplicateItem
                }
                genericPasswords[identity] = GenericRecord(
                    data: data,
                    label: query.label,
                    comment: query.comment,
                    accessibility: query.accessibility
                )
            case .internetPassword:
                let identity = internetIdentity(for: query)
                guard internetPasswords[identity] == nil else {
                    throw KeychainError.duplicateItem
                }
                internetPasswords[identity] = InternetRecord(
                    data: data,
                    accessibility: query.accessibility
                )
            #if Cryptography
                case .cryptographicKey:
                    throw KeychainError.platformUnsupported("Unsupported in test backend")
            #endif
            }
        }
    }

    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        try withLock {
            switch query.itemClass {
            case .genericPassword:
                if query.matchLimit == .all {
                    let items: [KeychainQueryResult] = genericPasswords.compactMap { identity, _ in
                        guard matchesGeneric(identity, query: query) else { return nil }
                        return KeychainQueryResult.attributes([
                            .account(identity.account ?? ""),
                            .service(identity.service ?? ""),
                        ])
                    }
                    guard !items.isEmpty else {
                        throw KeychainError.itemNotFound
                    }
                    return .items(items)
                }

                guard let record = genericPasswords[genericIdentity(for: query)] else {
                    throw KeychainError.itemNotFound
                }

                if query.returnData {
                    return .data(record.data)
                }
                if query.returnAttributes {
                    return .attributes([
                        .account(query.account ?? ""),
                        .service(query.service ?? ""),
                    ])
                }
                return .attributes([])
            case .internetPassword:
                guard let record = internetPasswords[internetIdentity(for: query)] else {
                    throw KeychainError.itemNotFound
                }
                if query.returnData {
                    return .data(record.data)
                }
                return .attributes([])
            #if Cryptography
                case .cryptographicKey:
                    throw KeychainError.platformUnsupported("Unsupported in test backend")
            #endif
            }
        }
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        try withLock {
            switch query.itemClass {
            case .genericPassword:
                let identity = genericIdentity(for: query)
                guard var record = genericPasswords[identity] else {
                    throw KeychainError.itemNotFound
                }
                if let data = attributes.data {
                    record.data = data
                }
                record.label = attributes.label
                record.comment = attributes.comment
                record.accessibility = attributes.accessibility
                genericPasswords[identity] = record
            case .internetPassword:
                let identity = internetIdentity(for: query)
                guard var record = internetPasswords[identity] else {
                    throw KeychainError.itemNotFound
                }
                if let data = attributes.data {
                    record.data = data
                }
                record.accessibility = attributes.accessibility
                internetPasswords[identity] = record
            #if Cryptography
                case .cryptographicKey:
                    throw KeychainError.platformUnsupported("Unsupported in test backend")
            #endif
            }
        }
    }

    func delete(matching query: KeychainQuery) throws {
        withLock {
            switch query.itemClass {
            case .genericPassword:
                genericPasswords = genericPasswords.filter { identity, _ in
                    !matchesGeneric(identity, query: query)
                }
            case .internetPassword:
                internetPasswords = internetPasswords.filter { identity, _ in
                    !matchesInternet(identity, query: query)
                }
            #if Cryptography
                case .cryptographicKey:
                    break
            #endif
            }
        }
    }

    private func genericIdentity(for query: KeychainQuery) -> GenericIdentity {
        GenericIdentity(
            service: query.service,
            account: query.account,
            accessGroup: query.accessGroup,
            isSynchronizable: query.isSynchronizable
        )
    }

    private func internetIdentity(for query: KeychainQuery) -> InternetIdentity {
        InternetIdentity(
            server: query.server,
            account: query.account,
            accessGroup: query.accessGroup,
            port: query.port,
            path: query.path,
            internetProtocol: query.internetProtocol,
            authenticationType: query.authenticationType
        )
    }

    private func matchesGeneric(_ identity: GenericIdentity, query: KeychainQuery) -> Bool {
        if let service = query.service, identity.service != service {
            return false
        }
        if let account = query.account, identity.account != account {
            return false
        }
        if let accessGroup = query.accessGroup, identity.accessGroup != accessGroup {
            return false
        }
        if let isSynchronizable = query.isSynchronizable, identity.isSynchronizable != isSynchronizable {
            return false
        }
        return true
    }

    private func matchesInternet(_ identity: InternetIdentity, query: KeychainQuery) -> Bool {
        if let server = query.server, identity.server != server {
            return false
        }
        if let account = query.account, identity.account != account {
            return false
        }
        if let accessGroup = query.accessGroup, identity.accessGroup != accessGroup {
            return false
        }
        if let port = query.port, identity.port != port {
            return false
        }
        if let path = query.path, identity.path != path {
            return false
        }
        if let internetProtocol = query.internetProtocol, identity.internetProtocol != internetProtocol {
            return false
        }
        if let authenticationType = query.authenticationType, identity.authenticationType != authenticationType {
            return false
        }
        return true
    }

    private func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private struct UnexpectedResultSecureStorageBackend: SecureStorageBackend {
    func add(_ query: KeychainQuery, data: Data) throws {}

    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        if query.matchLimit == .all {
            return .data(Data())
        }
        if query.returnData {
            return .attributes([])
        }
        return .data(Data())
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {}

    func delete(matching query: KeychainQuery) throws {}
}

private struct AlwaysFailingSecureStorageBackend: SecureStorageBackend {
    let error: KeychainError

    func add(_ query: KeychainQuery, data: Data) throws {
        throw error
    }

    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        throw error
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        throw error
    }

    func delete(matching query: KeychainQuery) throws {
        throw error
    }
}

@Test
func keychainActorGenericOperationsUseRealKeychainPaths() async throws {
    let keychain = Keychain(backend: TestSecureStorageBackend())
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
    let keychain = Keychain(backend: TestSecureStorageBackend())
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

@Test
func keychainActorUnexpectedDataPathsAreCovered() async throws {
    let keychain = Keychain(backend: UnexpectedResultSecureStorageBackend())
    let key = KeychainKey<String>(service: "tests.actor.unexpected", account: "token")
    let internetKey = InternetPasswordKey(server: "unexpected.example.com", account: "alice")

    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.load(key: key)
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.allAccounts(service: "tests.actor.unexpected")
    }
    await #expect(throws: KeychainError.unexpectedData) {
        try await keychain.loadInternetPassword(for: internetKey)
    }
}

@Test
func keychainActorPropagatesBackendFailures() async throws {
    let keychain = Keychain(backend: AlwaysFailingSecureStorageBackend(error: .unexpectedData))
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
        let keychain = Keychain(backend: TestSecureStorageBackend())
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
