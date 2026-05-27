# Using Macros

Reduce boilerplate with SwiftyChain's Swift macros.

## Overview

SwiftyChain ships three macros that generate keychain plumbing at compile
time, available out of the box with no extra trait required.

### @KeychainScope

Annotate a type to group related keychain items under a shared service
and gain a `static deleteAll()` helper that bulk-deletes every item
stored under that service:

```swift
@KeychainScope(service: "com.example.app")
final class Secrets {
    @KeychainItem("api-token")
    var apiToken: String?

    @KeychainItem("refresh-token")
    var refreshToken: String?
}

let secrets = Secrets()
try await secrets.setApiToken("abc123")   // saves to keychain
let token = try await secrets.apiToken    // loads; nil if absent
try await secrets.setApiToken(nil)        // deletes

try await Secrets.deleteAll()             // bulk-deletes all items for the service
```

The scope macro adds a `static func deleteAll()` to the annotated type.
`@KeychainItem` properties inside a scope omit `service:` —
the scope injects it automatically into every generated ``KeychainKey``.

### @KeychainItem

Attach to a stored property to generate a backing ``KeychainKey``, an
`async throws` computed getter, and a `setXyz(_:)` async peer method:

```swift
@KeychainItem(
    "device-secret",
    service: "com.example.app",
    accessibility: .whenPasscodeSetThisDeviceOnly
)
var deviceSecret: Data?
```

`service:` and the account (first argument) must be non-empty string
literals; the macro emits a compile-time diagnostic if either is empty.
Passing `nil` to the generated setter deletes the item; non-optional
properties always upsert.

### #keychainKey

A freestanding expression macro that creates a ``KeychainKey`` inline and
validates its string-literal arguments at compile time (for example,
flagging `isSynchronizable: true` combined with a `ThisDeviceOnly`
accessibility):

```swift
let key: KeychainKey<String> = #keychainKey(
    service: "com.example.app",
    account: "token"
)
```

## Testing Macro-Generated Code

`@KeychainItem` and `@KeychainScope` generate accessors that are hardcoded
to `Keychain.shared`. There is no injection point, so you cannot substitute
an `InMemoryKeychain` at the macro level.

For code that needs unit tests, use the protocol-based API instead:

```swift
// Testable: depends on KeychainProtocol, injectable in tests.
actor Credentials {
    private let keychain: any KeychainProtocol
    private let tokenKey = KeychainKey<String>(
        service: "com.example.app",
        account: "api-token"
    )

    init(keychain: any KeychainProtocol = Keychain.shared) {
        self.keychain = keychain
    }

    func token() async throws -> String? {
        try await keychain.loadIfPresent(key: tokenKey)
    }
}
```

Reserve `@KeychainItem` and `@KeychainScope` for types where you either:

- Test only the surrounding logic (not the keychain read/write itself), or
- Cover the keychain interaction with a narrow integration test against the
  real keychain on device.

See <doc:Testing> for guidance on when to use the real keychain versus
in-memory test doubles.
