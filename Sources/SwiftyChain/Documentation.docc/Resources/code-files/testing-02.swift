import SwiftyChain

actor TokenStore {
    private let keychain: any KeychainProtocol
    private let key = KeychainKey<String>(
        service: "com.example.myapp",
        account: "api-token"
    )

    init(keychain: any KeychainProtocol = Keychain.shared) {
        self.keychain = keychain
    }

    func save(token: String) async throws {
        try await keychain.upsert(token, for: key)
    }

    func load() async throws -> String? {
        try await keychain.loadIfPresent(key: key)
    }
}
