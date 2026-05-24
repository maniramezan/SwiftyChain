# ``SwiftyChain/DefaultedKeychainStorage``

## Overview

`@DefaultedKeychainStorage` provides synchronous, `@AppStorage`-shaped access to
keychain values that should always read as a concrete type.

Like ``KeychainStorage``, it talks directly to the keychain instead of going
through ``Keychain``, so writes do **not** emit observation events from
``Keychain/observeKeychainChanges(service:accessGroup:)``.

Use this wrapper when an absent value should be represented by a fallback
instead of `nil`.

```swift
struct Settings {
    @DefaultedKeychainStorage(
        "username",
        service: "com.example.app",
        defaultValue: ""
    )
    var username: String
}
```

The projected value (`$property`) exposes the last ``KeychainError``, if any.
The wrapped value returns `defaultValue` when the item is missing or a read fails.

> Important: `@DefaultedKeychainStorage` does not support deletion through `nil`
> assignment because the wrapped property is non-optional. Use ``KeychainStorage``
> when `nil` should delete the underlying item.

## Topics

### Creating

- ``init(_:service:defaultValue:accessGroup:accessibility:isSynchronizable:)``

### Accessing Values

- ``wrappedValue``
- ``projectedValue``
