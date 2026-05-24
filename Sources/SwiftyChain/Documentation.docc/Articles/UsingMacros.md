# Using Macros

Reduce boilerplate with SwiftyChain's Swift macros.

## Overview

SwiftyChain ships three macros that generate keychain plumbing at compile
time. They require the `macros` package trait to be enabled (see the
Installation section in <doc:SwiftyChain>) and Swift 5.9+.

### @KeychainScope

Annotate a type to gain a shared instance and a `deleteAll()` helper that
bulk-deletes every item stored under the given service:

```swift
@KeychainScope(service: "com.example.app")
final class Secrets {
    @KeychainItem(service: "com.example.app", account: "api-token")
    var apiToken: String?

    @KeychainItem(service: "com.example.app", account: "refresh-token")
    var refreshToken: String?
}

try await Secrets.shared.deleteAll()
```

The scope macro adds `static let shared = Self()` and `deleteAll()` to the
annotated type. Each `@KeychainItem` still declares its own service
explicitly so the generated ``KeychainKey`` is self-contained and usable
independently of the scope — you can pass `Secrets.apiTokenKey` to
``Keychain/load(key:)`` directly without going through the scope.

> Note: The `service` argument on each `@KeychainItem` does not have to
> match the `@KeychainScope` service, but it should for `deleteAll()` to
> cover all items in the scope. Keeping them in sync is a convention, not
> a compile-time requirement.

### @KeychainItem

Attach to a stored property to generate a backing ``KeychainKey``, an
`async throws` getter, and a `setXyz(_:)` async setter:

```swift
@KeychainItem(
    service: "com.example.app",
    account: "biometric-secret",
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
