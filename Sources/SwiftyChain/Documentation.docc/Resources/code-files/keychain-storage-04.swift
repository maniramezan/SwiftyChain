import SwiftyChain

struct SharedSecrets {
    @DefaultedKeychainStorage(
        "refresh-token",
        service: "com.example.myapp",
        defaultValue: "",
        accessGroup: "group.com.example.myapp",
        accessibility: .afterFirstUnlock,
        isSynchronizable: true
    )
    var refreshToken: String
}
