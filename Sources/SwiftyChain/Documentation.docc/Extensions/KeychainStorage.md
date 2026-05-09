# ``SwiftyChain/KeychainStorage``

## Overview

`@KeychainStorage` provides synchronous, `@AppStorage`-style access to
optional keychain values. It bypasses the ``Keychain`` actor and talks to
the keychain directly, so it does **not** trigger observation events.

The projected value (`$property`) exposes the last ``KeychainError``, if
any, letting you handle failures inline.

```swift
struct Settings {
    @KeychainStorage("api-token", service: "com.example.app")
    var token: String?
}

var settings = Settings()
settings.token = "sk-live-abc123"

if let error = settings.$token {
    print("Failed: \(error)")
}
```

## Topics

### Creating

- ``init(_:service:accessGroup:accessibility:isSynchronizable:defaultValue:)``

### Accessing Values

- ``wrappedValue``
- ``projectedValue``
