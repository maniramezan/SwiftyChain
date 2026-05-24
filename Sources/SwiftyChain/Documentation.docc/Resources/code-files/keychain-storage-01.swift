import SwiftyChain

struct SessionStore {
    @KeychainStorage("auth-token", service: "com.example.myapp")
    var authToken: String?
}
