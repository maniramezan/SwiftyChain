# ``SwiftyChain/KeychainBackend``

## Overview

`KeychainBackend` is the low-level storage protocol used by ``KeychainStorage``.
It operates on raw `Data` rather than typed values, which keeps the surface minimal
enough for downstream test fakes.

The `SwiftyChainTesting` product provides `InMemoryKeychainBackend`, a ready-made
in-memory implementation. Alternatively, conform your own type to this protocol
for custom storage needs.

```swift
// Inject a test backend when unit-testing @KeychainStorage-based code
let backend = InMemoryKeychainBackend() // from SwiftyChainTesting
let storage = KeychainStorage<String>("token", service: "com.example", backend: backend)
```

> Note: `KeychainBackend` is intentionally narrow. It does not cover internet passwords,
> cryptographic keys, or bulk deletion — those are handled by ``KeychainProtocol`` and
> the ``Keychain`` actor directly.

## Topics

### Saving and Updating

- ``save(_:service:account:accessGroup:accessibility:isSynchronizable:label:comment:)``
- ``update(_:service:account:accessGroup:accessibility:isSynchronizable:label:comment:)``

### Loading

- ``load(service:account:accessGroup:isSynchronizable:)``

### Deleting

- ``delete(service:account:accessGroup:isSynchronizable:)``
