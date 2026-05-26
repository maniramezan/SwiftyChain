# ``SwiftyChain/KeychainProtocol``

## Overview

`KeychainProtocol` is the dependency-injection interface for keychain operations.
Declare your feature code against it so tests can inject an in-memory implementation
without touching the real system keychain.

```swift
actor TokenStore {
    private let keychain: any KeychainProtocol
    private let key = KeychainKey<String>(service: "com.example", account: "token")

    init(keychain: any KeychainProtocol) { self.keychain = keychain }

    func save(_ token: String) async throws { try await keychain.upsert(token, for: key) }
    func load() async throws -> String?    { try await keychain.loadIfPresent(key: key) }
}
```

The `SwiftyChainTesting` product provides `InMemoryKeychain`, a full in-memory
implementation of this protocol for use in unit tests.

> Tip: Use ``Keychain/upsert(_:for:)`` for most writes — it creates or replaces in one call,
> with no error on either path.

## Topics

### Writing Values

- ``save(_:for:)``
- ``upsert(_:for:)``
- ``update(_:for:)``

### Reading Values

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
