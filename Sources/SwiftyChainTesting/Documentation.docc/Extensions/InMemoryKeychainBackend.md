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

`InMemoryKeychainBackend` uses `NSLock` to serialize all reads and writes, making
it safe to call from multiple threads or concurrent Swift tasks.

## Topics

### Creating

- ``init()``

### Reading and Writing

- ``save(_:service:account:accessGroup:accessibility:isSynchronizable:label:comment:)``
- ``load(service:account:accessGroup:isSynchronizable:)``
- ``update(_:service:account:accessGroup:accessibility:isSynchronizable:label:comment:)``
- ``delete(service:account:accessGroup:isSynchronizable:)``
