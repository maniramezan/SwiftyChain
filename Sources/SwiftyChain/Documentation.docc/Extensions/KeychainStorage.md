# ``SwiftyChain/KeychainStorage``

## Overview

`@KeychainStorage` provides synchronous, `@AppStorage`-shaped access to
optional keychain values. It bypasses the ``Keychain`` actor and reads or
writes the keychain directly, so changes do **not** emit observation
events from ``Keychain/observeKeychainChanges(service:accessGroup:)``.

Both the wrapped getter and setter are non-mutating, so you can hold a
`@KeychainStorage` property on a `let`, read it from a SwiftUI `View.body`,
or assign through it without marking the surrounding type `var`.

The projected value (`$property`) exposes the last ``KeychainError``, if
any. The error is updated under a lock for thread-safe access.

```swift
struct Settings {
    @KeychainStorage("api-token", service: "com.example.app")
    var token: String?
}

let settings = Settings()
settings.token = "sk-live-abc123"

if let error = settings.$token {
    print("Failed: \(error)")
}
```

> Important: Because writes do not go through ``Keychain``, observers
> registered with ``Keychain/observeKeychainChanges(service:accessGroup:)``
> will not see updates made through `@KeychainStorage`. If you need change
> notifications, use ``Keychain/shared`` directly.

## Topics

### Creating

- ``init(_:service:accessGroup:accessibility:isSynchronizable:defaultValue:)``

### Accessing Values

- ``wrappedValue``
- ``projectedValue``
