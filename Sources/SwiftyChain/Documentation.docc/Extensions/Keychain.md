# ``SwiftyChain/Keychain``

## Overview

`Keychain` is the primary entry point for all keychain operations. It is
declared as an `actor` so every method is automatically thread-safe.

Use the ``shared`` singleton for production code. In tests, create an
instance with a custom backend to avoid hitting the real keychain.

```swift
// Production
let token = try await Keychain.shared.load(key: myKey)

// Tests
let mock = MockKeychainBackend()
let keychain = Keychain(backend: mock)
```

## Topics

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

