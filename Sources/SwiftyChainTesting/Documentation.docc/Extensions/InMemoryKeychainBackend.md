# ``SwiftyChainTesting/InMemoryKeychainBackend``

## Overview

`InMemoryKeychainBackend` is a thread-safe implementation of `KeychainBackend`
that stores raw item data in memory. Use it when testing code that depends on
`KeychainStorage` directly.

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

### Isolation

Each `InMemoryKeychainBackend` instance is completely independent. Create a fresh
one per test to guarantee that tests do not share state.

### Thread safety

`InMemoryKeychainBackend` uses a `Mutex` to serialize all reads and writes, making
it safe to call from multiple threads or concurrent Swift tasks.

Pass `capabilities:` to reproduce restrictions. Use the same backend with
`Keychain(backend:)` to exercise the production engine. Each engine has a separate
observation registry even when the backend instance is shared.

## Topics

### Creating

- ``init(capabilities:)``
- ``capabilities``
- ``defaultCapabilities``

### Reading and Writing

- ``add(_:attributes:)``
- ``data(matching:)``
- ``contains(matching:)``
- ``accounts(matching:)``
- ``update(matching:to:)``
- ``delete(matching:)``
