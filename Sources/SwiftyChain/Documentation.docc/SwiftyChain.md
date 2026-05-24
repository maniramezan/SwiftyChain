# ``SwiftyChain``

Store and retrieve keychain values with Swift-native types.

## Overview

SwiftyChain wraps Apple's `SecItem*` APIs behind typed keys, a public `Keychain` actor, and a lightweight `@KeychainStorage` property wrapper. It is fully `Sendable`, actor-isolated, and supports Swift concurrency out of the box.

Key design goals:

- **Type safety** -- Generic ``KeychainKey`` descriptors prevent accidental type mismatches.
- **Concurrency** -- ``Keychain`` is an `actor`, so every operation is data-race free.
- **Testability** -- Depend on ``KeychainProtocol`` or inject a ``KeychainBackend`` to test without touching the real keychain.
- **Ergonomics** -- `@KeychainStorage` gives you `@AppStorage`-style property-wrapper access.

## Installation

Add SwiftyChain to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/maniramezan/SwiftyChain", from: "1.0.0"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "SwiftyChain", package: "SwiftyChain"),
        ]
    ),
]
```

### Optional Traits

SwiftyChain ships several opt-in traits that gate additional features at compile time. Enable only what you need:

| Trait | What it adds |
|---|---|
| `macros` | `@KeychainItem`, `@KeychainScope`, and `#keychainKey(...)` compile-time macros |
| `observation` | ``Keychain/observeKeychainChanges(service:accessGroup:)`` and ``KeychainChangeEvent`` |
| `cryptography` | ``Keychain/saveCryptoKey(_:for:)``, ``Keychain/loadCryptoKey(keyRef:)``, ``Keychain/deleteCryptoKey(keyRef:)``, ``CryptoKeyReference``, ``StoredSecKey`` |

Enable traits by passing them to the product dependency:

```swift
.product(
    name: "SwiftyChain",
    package: "SwiftyChain",
    traits: ["macros", "observation", "cryptography"]
)
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``Keychain``
- ``KeychainKey``

### Storing Values

- ``KeychainStorable``
- ``CodableKeychainStorable``
- <doc:CustomStorableTypes>

### Property Wrapper

- ``KeychainStorage``
- ``DefaultedKeychainStorage``
- <doc:SwiftyChainKeychainStorage>

### Test Support

- ``KeychainProtocol``
- ``KeychainBackend``
- <doc:Testing>

### Internet Passwords

- ``InternetPasswordKey``
- ``InternetProtocol``
- ``AuthenticationType``
- <doc:InternetPasswords>

### Accessibility and Security

- ``KeychainAccessibility``

### Bulk Deletion

- ``KeychainDeleteQuery``
- ``KeychainItemClass``

### Errors

- ``KeychainError``

### Observation

- ``KeychainChangeEvent``

### Macros

- <doc:UsingMacros>

### Cryptographic Keys

- ``CryptoKeyReference``
- ``StoredSecKey``
- ``CryptoKeyStorable``
