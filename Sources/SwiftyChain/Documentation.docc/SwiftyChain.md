# ``SwiftyChain``

Store and retrieve keychain values with Swift-native types.

## Overview

SwiftyChain wraps Apple's `SecItem*` APIs behind typed keys, a public `Keychain` actor, and a lightweight `@KeychainStorage` property wrapper. It is fully `Sendable`, actor-isolated, and supports Swift concurrency out of the box.

Key design goals:

- **Type safety** -- Generic ``KeychainKey`` descriptors prevent accidental type mismatches.
- **Concurrency** -- ``Keychain`` is an `actor`, so every operation is data-race free.
- **Testability** -- Inject a custom backend to unit-test without touching the real keychain.
- **Ergonomics** -- `@KeychainStorage` gives you `@AppStorage`-style property-wrapper access.

## Topics

### Essentials

- <doc:SwiftyChainTutorials>
- ``Keychain``
- ``KeychainKey``

### Storing Values

- ``KeychainStorable``
- ``CodableKeychainStorable``
- <doc:CustomStorableTypes>

### Property Wrapper

- ``KeychainStorage``

### Internet Passwords

- ``InternetPasswordKey``
- ``InternetProtocol``
- ``AuthenticationType``
- <doc:InternetPasswords>

### Accessibility and Security

- ``KeychainAccessibility``
- ``KeychainDeleteQuery``

### Errors

- ``KeychainError``

### Macros

- <doc:UsingMacros>
