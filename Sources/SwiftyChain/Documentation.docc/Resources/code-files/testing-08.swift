import SwiftyChain
import SwiftyChainTesting

enum AppDependencies {
    static let keychain: any KeychainProtocol = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["USE_MOCK_KEYCHAIN"] == "1" {
            return InMemoryKeychain()
        }
        #endif
        return Keychain.shared
    }()
}

@KeychainScope(service: "com.example.myapp", keychain: AppDependencies.keychain)
final class Secrets {
    @KeychainItem("api-token")
    var apiToken: String?
}
