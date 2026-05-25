import SwiftyChain

struct SharedSecrets {
    @KeychainStorage(
        "refresh-token",
        service: "com.example.myapp",
        accessGroup: "group.com.example.myapp",
        accessibility: .afterFirstUnlock,
        isSynchronizable: true
    )
    var refreshToken: String?
}
