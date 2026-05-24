import SwiftyChain
import SwiftyChainTesting
import Testing

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

@Test
func consumerCanUseDefaultedPropertyWrapper() throws {
    let backend = InMemoryKeychainBackend()
    let storage = DefaultedKeychainStorage<String>(
        "token",
        service: "consumer.tests",
        backend: backend,
        defaultValue: "fallback"
    )

    #expect(storage.wrappedValue == "fallback")

    storage.wrappedValue = "wrapped"

    #expect(storage.wrappedValue == "wrapped")
    #expect(storage.projectedValue == nil)
}
