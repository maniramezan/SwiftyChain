import Foundation
import Testing

@testable import SwiftyChain

private let integrationEnabled =
    ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_KEYCHAIN_INTEGRATION"] == "1"

@Test(.enabled(if: integrationEnabled))
func realKeychainRoundTrip() async throws {
    let service = "dev.manman.SwiftyChain.integration.\(UUID().uuidString)"
    let key = KeychainKey<String>(service: service, account: "token")

    try await Keychain.shared.upsert("secret", for: key)
    #expect(try await Keychain.shared.load(key: key) == "secret")

    try await Keychain.shared.delete(key: key)
    #expect(try await Keychain.shared.loadIfPresent(key: key) == nil)
}

@Test(.enabled(if: integrationEnabled))
func realKeychainUpdateAndExists() async throws {
    let service = "dev.manman.SwiftyChain.integration.update.\(UUID().uuidString)"
    let key = KeychainKey<String>(
        service: service,
        account: "user",
        label: "original label"
    )

    #expect(try await Keychain.shared.exists(key: key) == false)

    try await Keychain.shared.save("v1", for: key)
    #expect(try await Keychain.shared.exists(key: key))
    #expect(try await Keychain.shared.load(key: key) == "v1")

    let relabeled = KeychainKey<String>(
        service: service,
        account: "user",
        label: "new label"
    )
    try await Keychain.shared.update("v2", for: relabeled)
    #expect(try await Keychain.shared.load(key: key) == "v2")

    try await Keychain.shared.delete(key: key)
    #expect(try await Keychain.shared.exists(key: key) == false)
}

@Test(.enabled(if: integrationEnabled))
func realKeychainBulkDeleteByService() async throws {
    let service = "dev.manman.SwiftyChain.integration.bulk.\(UUID().uuidString)"
    try await Keychain.shared.save("a", for: KeychainKey<String>(service: service, account: "a"))
    try await Keychain.shared.save("b", for: KeychainKey<String>(service: service, account: "b"))

    let accounts = try await Keychain.shared.allAccounts(service: service)
    #expect(Set(accounts) == ["a", "b"])

    try await Keychain.shared.deleteAll(service: service)
    #expect(try await Keychain.shared.allAccounts(service: service).isEmpty)
}

@Test(.enabled(if: integrationEnabled))
func realKeychainInternetPasswordRoundTrip() async throws {
    let server = "swiftychain-integration-\(UUID().uuidString).example.com"
    let key = InternetPasswordKey(
        server: server,
        account: "alice",
        protocol: .https,
        authenticationType: .httpBasic
    )

    try await Keychain.shared.saveInternetPassword("pw", for: key)
    #expect(try await Keychain.shared.loadInternetPassword(for: key) == "pw")

    try await Keychain.shared.deleteInternetPassword(for: key)
    await #expect(throws: KeychainError.itemNotFound) {
        try await Keychain.shared.loadInternetPassword(for: key)
    }
}

@Test(.enabled(if: integrationEnabled))
func realKeychainPropertyWrapperRoundTrip() throws {
    let storage = KeychainStorage<String>(
        "wrapper-token",
        service: "dev.manman.SwiftyChain.integration.wrapper.\(UUID().uuidString)"
    )

    #expect(storage.wrappedValue == nil)

    storage.wrappedValue = "value"
    #expect(storage.wrappedValue == "value")

    storage.wrappedValue = nil
    #expect(storage.wrappedValue == nil)
    #expect(storage.projectedValue == nil)
}
