# Getting Started with SwiftyChain

Store and load your first keychain value in minutes.

## Overview

SwiftyChain replaces the raw `SecItem*` C API with three building blocks:

- **``KeychainKey``** — a typed descriptor that identifies a keychain item.
- **``Keychain``** — an `actor` that performs thread-safe CRUD operations.
- **``KeychainStorage``** — property wrapper for synchronous, `@AppStorage`-style access.

This article walks through a complete first-use example using the `Keychain` actor. For SwiftUI-centric usage see ``KeychainStorage``.

## Define a Key

A ``KeychainKey`` is a compile-time descriptor that ties a keychain item to a specific Swift type. Create one constant per value you want to store:

```swift
import SwiftyChain

// Stores a String under service "com.example.app", account "auth-token"
let authTokenKey = KeychainKey<String>(
    service: "com.example.app",
    account: "auth-token"
)
```

The generic parameter (`String` here) is enforced at compile time — you cannot accidentally load a `Bool` from a `KeychainKey<String>`.

> Tip: Define your keys as `static let` constants in a dedicated namespace so they are easy to find and cannot be accidentally duplicated with different parameters.

```swift
enum KeychainKeys {
    static let authToken   = KeychainKey<String>(service: "com.example.app", account: "auth-token")
    static let sessionBlob = KeychainKey<Data>(service: "com.example.app", account: "session-blob")
    static let launchCount = KeychainKey<Int>(service: "com.example.app", account: "launch-count")
}
```

## Write a Value

Use ``Keychain/upsert(_:for:)`` to save or replace a value. It is the recommended write method because it creates the item if it does not exist and updates it if it does:

```swift
try await Keychain.shared.upsert("eyJhbGciOiJIUzI1NiJ9", for: KeychainKeys.authToken)
```

If you need to detect whether an item already exists, use ``Keychain/save(_:for:)`` (fails with ``KeychainError/duplicateItem`` on conflict) or ``Keychain/update(_:for:)`` (fails with ``KeychainError/itemNotFound`` if absent).

## Read a Value

```swift
let token = try await Keychain.shared.load(key: KeychainKeys.authToken)
```

If you are not sure whether the value has been stored yet, use ``Keychain/loadIfPresent(key:)`` to get an optional instead of an error:

```swift
if let token = try await Keychain.shared.loadIfPresent(key: KeychainKeys.authToken) {
    // use token
} else {
    // first launch — nothing stored yet
}
```

## Handle Errors

All operations throw ``KeychainError``. The most common cases to handle:

```swift
do {
    let token = try await Keychain.shared.load(key: KeychainKeys.authToken)
    use(token)
} catch KeychainError.itemNotFound {
    // No token stored yet — redirect to login
} catch KeychainError.authenticationFailed {
    // User declined biometric prompt — ask again or fall back
} catch {
    // Unexpected failure
    print("Keychain error:", error)
}
```

## Delete a Value

```swift
// Delete one item
try await Keychain.shared.delete(key: KeychainKeys.authToken)

// Delete all items for a service (e.g., on sign-out)
try await Keychain.shared.deleteAll(service: "com.example.app")
```

## Next Steps

- **Custom types** — Conform your own `Codable` or custom types to ``KeychainStorable``. See <doc:CustomStorableTypes>.
- **Internet passwords** — Store credentials associated with a server and protocol. See <doc:InternetPasswords>.
- **SwiftUI** — Use ``KeychainStorage`` for optional values. For non-optional access, use `@KeychainItem`. See <doc:SwiftyChainKeychainStorage> and <doc:UsingMacros>.
- **Macros** — Reduce boilerplate with `@KeychainItem` and `@KeychainScope`. See <doc:UsingMacros>.
- **iCloud sync** — Set `isSynchronizable: true` on a ``KeychainKey`` to sync the value across the user's devices via iCloud Keychain.
