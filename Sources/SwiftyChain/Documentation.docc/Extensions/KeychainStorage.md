# ``SwiftyChain/KeychainStorage``

## Overview

`@KeychainStorage` provides synchronous, `@AppStorage`-shaped access to
optional keychain values. It uses the same engine as ``Keychain``. Platform-backed
wrappers emit events to observers shared with ``Keychain/shared``; a custom backend
has a separate observer registry per engine. Calls run synchronously on the caller's thread.

Use the initializer when you want property-wrapper ergonomics without
manually creating a ``KeychainKey``. The minimal call requires:

- `account` — the unique name for the stored item, such as `"auth-token"`.
- `service` — the namespace that groups your app's keychain items, usually your bundle identifier.

The remaining parameters are optional:

- `accessGroup` — use when the value must be shared between multiple apps or extensions.
- `accessibility` — defaults to `nil`: platform default on add, unchanged on update.
- `accessControl` — requires user presence, biometry, or device passcode where supported.
- `configuration` — selects the macOS legacy or data-protection store.
- `isSynchronizable` — set to `true` to participate in iCloud Keychain sync (Apple platforms only).

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

### Non-Optional Access

When the property should always have a concrete value, use `@KeychainItem`.
The macro inspects the declared type and generates a non-throwing load that
returns the value directly:

```swift
@KeychainScope(service: "com.example.myapp")
class Preferences {
    @KeychainItem("has-onboarded")
    var hasOnboarded: Bool
}
```

See <doc:UsingMacros> for full details.

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

Pass `configuration: .init(macOSStore: .dataProtection)` to select the macOS
data-protection keychain, or `accessControl: .userPresence` to require authentication.
The default macOS legacy store rejects access control. See <doc:MigratingTo2>.

## Topics

### Creating

- ``init(_:service:accessGroup:accessibility:accessControl:isSynchronizable:configuration:)``

### Accessing Values

- ``wrappedValue``
- ``projectedValue``

### Related

- <doc:UsingMacros>
