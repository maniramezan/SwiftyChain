import SwiftyChain

let apiTokenKey = KeychainKey<String>(
    service: "com.example.myapp",
    account: "api-token"
)

func cleanup() async throws {
    // Delete a single item
    try await Keychain.shared.delete(key: apiTokenKey)

    // Delete all items for a service
    try await Keychain.shared.deleteAll(service: "com.example.myapp")
}
