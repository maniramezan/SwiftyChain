import SwiftyChain

let apiTokenKey = KeychainKey<String>(
    service: "com.example.myapp",
    account: "api-token"
)

func loadToken() async throws -> String? {
    try await Keychain.shared.loadIfPresent(key: apiTokenKey)
}
