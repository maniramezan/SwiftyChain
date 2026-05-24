import SwiftyChain

struct SharedSecrets {
    @KeychainStorage(
        "refresh-token",
        service: "com.example.myapp",
        accessGroup: "group.com.example.myapp",
        accessibility: .afterFirstUnlock,
        isSynchronizable: true,
        defaultValue: ""
    )
    var refreshToken: String?
}
