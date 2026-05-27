# ``SwiftyChainTesting/InMemoryKeychain``

## Overview

`InMemoryKeychain` is a full, actor-isolated implementation of `KeychainProtocol`
that stores items in memory. Use it in place of the real `Keychain` when your
feature code is written against `KeychainProtocol`.

```swift
import SwiftyChain
import SwiftyChainTesting

let keychain: any KeychainProtocol = InMemoryKeychain()
let key = KeychainKey<String>(service: "com.example", account: "token")

try await keychain.upsert("secret", for: key)
```

Create a new instance per test to ensure each test starts from a clean state.

### Conditional APIs

When the `observation` trait is enabled, `InMemoryKeychain` implements
`observeKeychainChanges(service:accessGroup:)`. Events are delivered
synchronously during each mutation, so you can consume the stream in the same async
test body:

```swift
import SwiftyChain
import SwiftyChainTesting
import Testing

@Test func emitsChangeEvent() async throws {
    let keychain = InMemoryKeychain()
    let key = KeychainKey<String>(service: "com.example", account: "token")
    var events: [KeychainChangeEvent] = []

    let stream = await keychain.observeKeychainChanges(service: "com.example")
    let task = Task {
        for await event in stream { events.append(event) }
    }

    try await keychain.upsert("secret", for: key)
    task.cancel()

    #expect(events.count == 1)
    #expect(events[0].kind == .saved)
}
```

When the `cryptography` trait is enabled, `InMemoryKeychain` also implements the
crypto-key CRUD methods:

```swift
let keyRef = CryptoKeyReference<StoredSecKey>(tag: "com.example.signing-key")
let storedKey = StoredSecKey(/* your generated SecKey */)
try await keychain.saveCryptoKey(storedKey, for: keyRef)
let loaded = try await keychain.loadCryptoKey(keyRef: keyRef)
```

## Topics

### Creating

- ``init()``

### Generic Passwords

- ``save(_:for:)``
- ``upsert(_:for:)``
- ``update(_:for:)``
- ``load(key:)``
- ``loadIfPresent(key:)``
- ``exists(key:)``
- ``delete(key:)``
- ``deleteAll(service:accessGroup:)``
- ``deleteAllSynchronizable(service:accessGroup:)``
- ``deleteAllItems(matching:)``
- ``allAccounts(service:accessGroup:)``

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
