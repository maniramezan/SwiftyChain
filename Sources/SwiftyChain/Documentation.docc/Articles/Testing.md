# Testing with SwiftyChain

Test keychain-dependent code without touching the real Apple keychain.

## Overview

SwiftyChain ships a separate `SwiftyChainTesting` product for downstream tests.

It provides two public test doubles:

- `InMemoryKeychain` for code that depends on ``KeychainProtocol``.
- `InMemoryKeychainBackend` for code that uses ``KeychainStorage``.

## Add the Testing Product

Add `SwiftyChainTesting` to your test target only:

```swift
.testTarget(
    name: "MyFeatureTests",
    dependencies: [
        .product(name: "SwiftyChain", package: "SwiftyChain"),
        .product(name: "SwiftyChainTesting", package: "SwiftyChain"),
    ]
)
```

## Test Actor-Based Code

Depend on ``KeychainProtocol`` in your feature code, then use `InMemoryKeychain` in tests.

```swift
import SwiftyChain
import SwiftyChainTesting

let keychain: any KeychainProtocol = InMemoryKeychain()
let tokenKey = KeychainKey<String>(service: "com.example.app", account: "auth-token")

try await keychain.upsert("secret", for: tokenKey)
let token = try await keychain.load(key: tokenKey)
```

## Test Property-Wrapper Code

Use `InMemoryKeychainBackend` when initializing ``KeychainStorage`` directly.

```swift
import SwiftyChain
import SwiftyChainTesting

let backend = InMemoryKeychainBackend()
let storage = KeychainStorage<String>(
    "auth-token",
    service: "com.example.app",
    backend: backend
)

storage.wrappedValue = "secret"
assert(storage.wrappedValue == "secret")
```

## When to Use the Real Keychain

Use the real keychain only for integration coverage, such as validating entitlements,
platform behavior, or Security.framework interoperability. Keep most unit tests on the
in-memory test doubles for speed and isolation.
