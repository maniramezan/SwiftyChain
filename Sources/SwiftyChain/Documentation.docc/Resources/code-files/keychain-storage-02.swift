import SwiftyChain

struct SessionStore {
    @KeychainStorage("auth-token", service: "com.example.myapp")
    var authToken: String?
}

var session = SessionStore()

session.authToken = "sk-live-123"
let currentToken = session.authToken

session.authToken = nil
