import SwiftyChain

struct Settings {
    @DefaultedKeychainStorage("api-token", service: "com.example.myapp", defaultValue: "")
    var token: String
}

var settings = Settings()

// Write
settings.token = "sk-new-token"

// Read
print("Token: \(settings.token)")

// Check for errors via the projected value
if let error = settings.$token {
    print("Keychain error: \(error)")
}
