import SwiftyChain

struct Settings {
    @KeychainStorage("api-token", service: "com.example.myapp")
    var token: String?
}

var settings = Settings()

// Write
settings.token = "sk-new-token"

// Read
if let token = settings.token {
    print("Token: \(token)")
}

// Check for errors via the projected value
if let error = settings.$token {
    print("Keychain error: \(error)")
}
