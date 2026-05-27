import SwiftyChain
import SwiftyChainTesting
import Testing

@Test func storageRoundTrip() {
    let backend = InMemoryKeychainBackend()
    let storage = KeychainStorage<String>(
        "api-token",
        service: "com.example.myapp",
        backend: backend
    )

    storage.wrappedValue = "secret"

    #expect(storage.wrappedValue == "secret")
}

@Test func storageReturnsNilWhenEmpty() {
    let backend = InMemoryKeychainBackend()
    let storage = KeychainStorage<String>(
        "api-token",
        service: "com.example.myapp",
        backend: backend
    )

    #expect(storage.wrappedValue == nil)
}
