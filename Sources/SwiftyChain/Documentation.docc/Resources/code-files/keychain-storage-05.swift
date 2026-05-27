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

    storage.wrappedValue = "sk-new-token"

    #expect(storage.wrappedValue == "sk-new-token")
}
