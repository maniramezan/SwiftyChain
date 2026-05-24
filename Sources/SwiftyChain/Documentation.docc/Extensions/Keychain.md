# ``SwiftyChain/Keychain``

## Overview

`Keychain` is the primary entry point for all keychain operations. It is
declared as an `actor` so every method is automatically thread-safe.

Use the ``shared`` singleton for production code. In tests, depend on
``KeychainProtocol`` and use `SwiftyChainTesting.InMemoryKeychain` to avoid
hitting the real keychain.

```swift
// Production
let token = try await Keychain.shared.load(key: myKey)

// Tests
let keychain: any KeychainProtocol = InMemoryKeychain()
```

### Choosing the Right Write Method

> Tip: Prefer ``upsert(_:for:)`` for most writes — it creates the item if it
> does not exist or replaces it if it does, in one call. Use ``save(_:for:)``
> only when you want to detect a duplicate explicitly, and ``update(_:for:)``
> only when you are certain the item already exists.

### Observation and @KeychainStorage

> Note: Changes made through ``KeychainStorage`` bypass the `Keychain` actor
> and do **not** emit observation events from
> ``observeKeychainChanges(service:accessGroup:)``. If you need change
> notifications, perform writes through ``Keychain/shared`` directly.

## Topics

### Shared Instance

- ``shared``

### Creating a Keychain

- ``init()``

### Saving Values

- ``save(_:for:)``
- ``upsert(_:for:)``
- ``update(_:for:)``

### Loading Values

- ``load(key:)``
- ``loadIfPresent(key:)``
- ``exists(key:)``
- ``allAccounts(service:accessGroup:)``

### Deleting Values

- ``delete(key:)``
- ``deleteAll(service:accessGroup:)``
- ``deleteAllSynchronizable(service:accessGroup:)``
- ``deleteAllItems(matching:)``

### Internet Passwords

- ``saveInternetPassword(_:for:)``
- ``loadInternetPassword(for:)``
- ``deleteInternetPassword(for:)``

### Observation

- ``observeKeychainChanges(service:accessGroup:)``

### Cryptographic Keys

- ``saveCryptoKey(_:for:)``
- ``loadCryptoKey(keyRef:)``
- ``deleteCryptoKey(keyRef:)``
