# ``SwiftyChainTesting``

Test keychain-dependent code without touching the real Apple keychain.

## Overview

`SwiftyChainTesting` is a companion product for `SwiftyChain` that ships two in-memory
test doubles. Add it to your test targets to run fast, isolated keychain tests that
require no entitlements and leave no items behind in the system keychain.

```swift
.testTarget(
    name: "MyFeatureTests",
    dependencies: [
        .product(name: "SwiftyChain", package: "SwiftyChain"),
        .product(name: "SwiftyChainTesting", package: "SwiftyChain"),
    ]
)
```

## Choosing a test double

| Your code depends on… | Use in tests… |
|---|---|
| `some KeychainProtocol` | ``InMemoryKeychain`` |
| `@KeychainStorage` / `KeychainBackend` | ``InMemoryKeychainBackend`` |

### `InMemoryKeychain`

Use this when your feature code is written against `KeychainProtocol`.

```swift
import SwiftyChain
import SwiftyChainTesting
import Testing

@Test func storesToken() async throws {
    let keychain: any KeychainProtocol = InMemoryKeychain()
    let key = KeychainKey<String>(service: "com.example", account: "token")

    try await keychain.upsert("secret", for: key)

    #expect(try await keychain.load(key: key) == "secret")
}
```

### `InMemoryKeychainBackend`

Use this when your feature uses `@KeychainStorage` or `KeychainStorage` directly.

```swift
import SwiftyChain
import SwiftyChainTesting
import Testing

@Test func storageRoundTrip() {
    let backend = InMemoryKeychainBackend()
    let storage = KeychainStorage<String>(
        "auth-token",
        service: "com.example.app",
        backend: backend
    )

    storage.wrappedValue = "secret"

    #expect(storage.wrappedValue == "secret")
}
```

## Topics

### Test Doubles

- ``InMemoryKeychain``
- ``InMemoryKeychainBackend``
