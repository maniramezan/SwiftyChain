# Architecture

## Module Layout

```
SwiftyChain/
├── Package.swift
├── Sources/
│   ├── SwiftyChain/                             # Main library target
│   │   ├── Core/
│   │   │   ├── KeychainError.swift
│   │   │   ├── KeychainKey.swift
│   │   │   ├── KeychainAccessibility.swift
│   │   │   ├── KeychainStorable.swift
│   │   │   └── KeychainItemClass.swift
│   │   ├── Backend/
│   │   │   ├── SecureStorageBackend.swift       # Protocol
│   │   │   └── AppleKeychainBackend.swift       # Apple SecItem* implementation
│   │   ├── Keychain.swift                       # Public actor
│   │   ├── PropertyWrapper/
│   │   │   └── KeychainStorage.swift            # @KeychainStorage
│   │   └── Extensions/
│   │       ├── KeychainStorable+Builtins.swift  # String, Data, Int, Bool, Codable
│   │       └── KeychainKey+Builders.swift       # Convenience factory methods
│   ├── SwiftyChainMacros/                       # Compiler plugin (always included)
│   │   ├── KeychainItemMacro.swift
│   │   ├── KeychainScopeMacro.swift
│   │   ├── KeychainKeyMacro.swift
│   │   └── SwiftyChainMacrosPlugin.swift
│   └── SwiftyChainTesting/                      # Test-support library (separate product)
│       └── InMemoryKeychain.swift
└── Tests/
    ├── SwiftyChainTests/
    ├── SwiftyChainTestingTests/
    └── SwiftyChainMacrosTests/
```

## Backend Protocol

`SecureStorageBackend` is the single seam between Swift-native types and the OS keychain:

```
Keychain actor  →  SecureStorageBackend  →  AppleKeychainBackend  →  SecItem* (C)
                                        ↗  InMemoryKeychainBackend (tests)
```

`AppleKeychainBackend` is the **only** place that touches `CFDictionary`/`CFTypeRef`. Every other layer — actor, property wrapper, macros, test mocks — works with `Sendable` Swift value types (`KeychainQuery`, `KeychainAttributes`, `KeychainQueryResult`). This keeps strict concurrency checking happy and makes a future `WindowsCredentialBackend` straightforward to add without touching existing code.

## Concurrency Model

`Keychain` is a regular `actor` (not `@globalActor`). All calls require `await`. `SecItem*` functions are synchronous C calls — they are wrapped so they run off the main thread, avoiding UI stalls.

`@KeychainStorage` is synchronous and calls `AppleKeychainBackend` directly (bypassing the actor) because `SecItem*` is thread-safe and brief. It is intended for `@MainActor`-isolated types only.

## Optional Traits

Two SPM traits gate optional features. Neither is enabled by default.

| Trait | Feature | Swift compile condition |
|-------|---------|------------------------|
| `cryptography` | `kSecClassKey` / `SecKey` storage | `#if Cryptography` |
| `observation` | `AsyncSequence` keychain change stream | `#if Observation` |

Macros (`@KeychainItem`, `@KeychainScope`, `#keychainKey`) are **always included** — they have no external dependencies beyond `swift-syntax`, which is already required.

## Platform Notes

All six Apple platforms share the `SecItem*` API. Platform-specific divergences are handled with `#if os(...)` guards:

| Divergence | Platforms affected |
|------------|-------------------|
| `whenPasscodeSetThisDeviceOnly` unavailable | tvOS |
| User-presence / biometric protection unavailable | tvOS |
| iCloud Keychain sync (`isSynchronizable`) unavailable | tvOS |
| Access groups require entitlements | iOS, iPadOS, visionOS |
| Multiple keychains, ACLs | macOS only |

## Future: Windows / Linux

`Security.framework` does not exist on Windows or Linux. A future `WindowsCredentialBackend` (v2.0) would conform to `SecureStorageBackend` and be gated with `#if os(Windows)` — no changes to the public API required.
