import SwiftyChain
import SwiftyChainTesting
import Testing

@Test func savesAndLoadsToken() async throws {
    let keychain = InMemoryKeychain()
    let store = TokenStore(keychain: keychain)

    try await store.save(token: "secret")

    #expect(try await store.load() == "secret")
}
