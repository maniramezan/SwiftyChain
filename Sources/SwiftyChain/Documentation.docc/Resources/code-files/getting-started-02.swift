import SwiftyChain

let apiTokenKey = KeychainKey<String>(
    service: "com.example.myapp",
    account: "api-token"
)

func saveToken(_ token: String) async throws {
    try await Keychain.shared.save(token, for: apiTokenKey)
}
