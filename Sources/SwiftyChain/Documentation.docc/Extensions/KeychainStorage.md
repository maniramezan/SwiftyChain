# ``SwiftyChain/KeychainStorage``

## Overview

`@KeychainStorage` provides synchronous, `@AppStorage`-shaped access to
optional keychain values. It bypasses the ``Keychain`` actor and reads or
writes the keychain directly, so changes do **not** emit observation
events from ``Keychain/observeKeychainChanges(service:accessGroup:)``.

Use the initializer when you want property-wrapper ergonomics without
manually creating a ``KeychainKey``. The minimal call requires:

- `account` — the unique name for the stored item, such as `"auth-token"`.
- `service` — the namespace that groups your app's keychain items, usually your bundle identifier.

The remaining parameters are optional:

- `accessGroup` — use when the value must be shared between multiple apps or extensions.
- `accessibility` — controls when the item can be read, such as `.whenUnlocked`.
- `isSynchronizable` — set to `true` to participate in iCloud Keychain sync.

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

## Usage Examples

### Minimal Setup

Use this when you only need a single value stored inside your app:

```swift
import SwiftyChain

struct SessionStore {
    @KeychainStorage("auth-token", service: "com.example.myapp")
    var authToken: String?
}
```

### Provide a Default Value

Use ``SwiftyChain/DefaultedKeychainStorage`` when the property should always
read as a concrete value instead of an optional:

```swift
struct Preferences {
    @DefaultedKeychainStorage(
        "has-onboarded",
        service: "com.example.myapp",
        defaultValue: false
    )
    var hasOnboarded: Bool
}
```

### Share with an App Group

Pass `accessGroup` when the same value must be readable from an app target
and an extension signed with the same keychain group entitlement:

```swift
struct SharedCredentials {
    @KeychainStorage(
        "session-id",
        service: "com.example.myapp",
        accessGroup: "group.com.example.myapp"
    )
    var sessionID: String?
}
```

### Customize Security and Sync Behavior

Choose a different accessibility level or turn on iCloud Keychain sync when
your product requires it:

```swift
struct SyncedSecrets {
    @KeychainStorage(
        "refresh-token",
        service: "com.example.myapp",
        accessibility: .afterFirstUnlock,
        isSynchronizable: true
    )
    var refreshToken: String?
}
```

> Important: Because writes do not go through ``Keychain``, observers
> registered with ``Keychain/observeKeychainChanges(service:accessGroup:)``
> will not see updates made through `@KeychainStorage`. If you need change
> notifications, use ``Keychain/shared`` directly.

## Topics

### Creating

- ``init(_:service:accessGroup:accessibility:isSynchronizable:)``

### Accessing Values

- ``wrappedValue``
- ``projectedValue``

### Related

- ``DefaultedKeychainStorage``
