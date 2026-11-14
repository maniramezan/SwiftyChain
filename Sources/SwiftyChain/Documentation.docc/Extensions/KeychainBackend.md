# ``SwiftyChain/KeychainBackend``

## Overview

Implement this public storage contract and pass it to ``Keychain/init(backend:)`` or a
``KeychainStorage`` initializer. ``KeychainQuery`` contains matching attributes only;
``KeychainAttributes`` contains secret data and write policy. The engine handles typed
serialization, capability validation, upsert, and observation for every backend.

```swift
import SwiftyChain
import SwiftyChainTesting

let backend = InMemoryKeychainBackend()
let keychain = Keychain(backend: backend)
let storage = KeychainStorage<String>("token", service: "com.example", backend: backend)
```

A `nil` query attribute matches any value. `isSynchronizable: nil` matches local and
synchronized items. An unset write attribute uses the platform default on add and leaves
existing policy unchanged on update. Adding a duplicate throws ``KeychainError/duplicateItem``;
reading or updating a missing item throws ``KeychainError/itemNotFound``. Delete succeeds
when no item matches. `contains` and `accounts` return empty results for missing items.

Declare optional features in ``capabilities``. `SwiftyChainTesting.InMemoryKeychainBackend`
accepts a capability set for emulation. Crypto storage uses the public `KeychainCryptoBackend`
refinement with the `cryptography` trait on Apple platforms.

Platform-backed engines share observers. A custom backend gets a separate observer registry
per engine, including when passed to multiple `Keychain` or `KeychainStorage` instances.
See <doc:MigratingTo2>.

## Topics

### Capabilities

- ``capabilities``

### Writing

- ``add(_:attributes:)``
- ``update(matching:to:)``
- ``delete(matching:)``

### Reading

- ``data(matching:)``
- ``contains(matching:)``
- ``accounts(matching:)``
