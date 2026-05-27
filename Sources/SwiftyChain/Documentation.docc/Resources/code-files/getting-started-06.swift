import SwiftyChain

// Depend on KeychainProtocol, not the concrete Keychain actor.
// Pass Keychain.shared at the call site in production.
// Pass InMemoryKeychain() from tests.
func saveToken(_ token: String, to keychain: any KeychainProtocol) async throws {
    let key = KeychainKey<String>(service: "com.example.myapp", account: "api-token")
    try await keychain.upsert(token, for: key)
}

func loadToken(from keychain: any KeychainProtocol) async throws -> String? {
    let key = KeychainKey<String>(service: "com.example.myapp", account: "api-token")
    return try await keychain.loadIfPresent(key: key)
}
