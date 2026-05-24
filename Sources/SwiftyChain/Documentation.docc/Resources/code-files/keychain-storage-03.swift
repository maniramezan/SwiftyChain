import SwiftyChain

struct SessionStore {
    @KeychainStorage("auth-token", service: "com.example.myapp")
    var authToken: String?
}

let session = SessionStore()

if let error = session.$authToken {
    print("Keychain error: \(error)")
}
