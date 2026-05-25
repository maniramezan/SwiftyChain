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

try await Secrets.deleteAll()
```

The scope macro adds a `static func deleteAll()` to the annotated type.
`@KeychainItem` properties inside a scope omit `service:` —
the scope injects it automatically into every generated ``KeychainKey``.

### @KeychainItem

Attach to a stored property to generate a backing ``KeychainKey``, an
`async throws` getter, and a `setXyz(_:)` async setter:

```swift
@KeychainItem(
    "biometric-secret",
    service: "com.example.app",
    accessibility: .whenPasscodeSetThisDeviceOnly
)
var biometricSecret: Data?
```

`service:` and `account:` must be non-empty string literals; the macro
emits a compile-time diagnostic if either is empty. Optional properties
generate a setter that deletes when assigned `nil`; non-optional
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
