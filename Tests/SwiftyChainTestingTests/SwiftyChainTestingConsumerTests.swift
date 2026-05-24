import Testing
import SwiftyChain
import SwiftyChainTesting

@Test
func consumerCanUseInMemoryKeychainThroughProtocol() async throws {
    let keychain: any KeychainProtocol = InMemoryKeychain()
    let key = KeychainKey<String>(service: "consumer.tests", account: "token")

    try await keychain.save("abc", for: key)

    #expect(try await keychain.load(key: key) == "abc")
    #expect(try await keychain.exists(key: key))
}

@Test
func consumerCanUseInMemoryBackendWithPropertyWrapper() throws {
    let backend = InMemoryKeychainBackend()
    let storage = KeychainStorage<String>(
        "token",
        service: "consumer.tests",
        backend: backend
    )

    storage.wrappedValue = "wrapped"

    #expect(storage.wrappedValue == "wrapped")
    #expect(storage.projectedValue == nil)
}
