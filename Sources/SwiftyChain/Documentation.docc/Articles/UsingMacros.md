# Using Macros

Reduce boilerplate with SwiftyChain's Swift macros.

## Overview

SwiftyChain includes three macros that generate keychain plumbing at
compile time. They require the `SwiftyChainMacros` module and Swift 5.9+.

### @KeychainScope

Annotate a class or struct to set a default service (and optional access
group) for all keychain items declared inside it:

```swift
@KeychainScope(service: "com.example.app")
final class Secrets {
    @KeychainItem(account: "api-token")
    var apiToken: String?

    @KeychainItem(account: "refresh-token")
    var refreshToken: String?
}
```

The macro generates the `KeychainKey` definitions and accessor code so you
can read and write properties directly.

### @KeychainItem

Attach to a stored property inside a `@KeychainScope` type. It generates:

- A backing `KeychainKey` constant.
- A computed getter and setter that call through to the keychain.

You can override per-property settings:

```swift
@KeychainItem(
    account: "biometric-secret",
    accessibility: .whenPasscodeSetThisDeviceOnly,
    isSynchronizable: false
)
var biometricSecret: Data?
```

### #keychainKey

A freestanding expression macro that creates a ``KeychainKey`` inline:

```swift
let key = #keychainKey<String>(
    service: "com.example.app",
    account: "token"
)
```

This is equivalent to calling the `KeychainKey` initializer but can be
extended in the future with compile-time validation.
