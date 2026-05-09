import Foundation
import Testing

@testable import SwiftyChain

@Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_KEYCHAIN_INTEGRATION"] == "1"))
func realKeychainRoundTrip() async throws {
    let service = "dev.manman.SwiftyChain.integration.\(UUID().uuidString)"
    let key = KeychainKey<String>(service: service, account: "token")

    try await Keychain.shared.upsert("secret", for: key)
    #expect(try await Keychain.shared.load(key: key) == "secret")

    try await Keychain.shared.delete(key: key)
    #expect(try await Keychain.shared.loadIfPresent(key: key) == nil)
}
