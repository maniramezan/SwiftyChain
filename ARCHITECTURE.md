# Architecture

The user-facing overview lives in the DocC article
[Architecture](Sources/SwiftyChain/Documentation.docc/Articles/Architecture.md). This file is
for contributors: where code lives and the rules each layer follows.

## Module Layout

```
SwiftyChain/
├── Package.swift
├── Sources/
│   ├── SwiftyChainCore/                 # Public value types + backend contract (re-exported)
│   │   ├── Values/                      # KeychainKey, KeychainError, KeychainStorable, ...
│   │   ├── Contract/                    # SecureStorageBackend, KeychainQuery, capabilities
│   │   └── Logging/                     # os.Logger on Apple, swift-log elsewhere
│   ├── SwiftyChain/                     # Public API
│   │   ├── Keychain.swift               # Public actor
│   │   ├── KeychainEngine.swift         # Platform-neutral logic shared by every backend
│   │   ├── KeychainExecutor.swift       # Linux-only serial executor for the actor
│   │   ├── PlatformDefaultBackend.swift # Picks the backend; fallback for other platforms
│   │   ├── PropertyWrapper/             # @KeychainStorage
│   │   └── Macros.swift, Crypto.swift, Observation.swift, ...
│   ├── SwiftyChainAppleKeychain/        # Apple backend (SecItem*)
│   ├── SwiftyChainSecretService/        # Linux backend (libsecret via CSwiftyChainSecret)
│   ├── CSwiftyChainSecret/              # dlopen-based libsecret loader (C)
│   ├── SwiftyChainMacros/               # Compiler plugin (always included)
│   └── SwiftyChainTesting/              # InMemoryKeychain (separate product)
└── Tests/
    ├── SwiftyChainTests/
    ├── SwiftyChainContractTests/        # One suite run against every backend
    ├── SwiftyChainSecretServiceTests/
    ├── SwiftyChainTestingTests/
    └── SwiftyChainMacrosTests/
```

## Backend Contract

`SecureStorageBackend` is the single seam between Swift value types and a platform keychain:

```
Keychain actor ─┐
KeychainStorage ┼→ KeychainEngine → SecureStorageBackend ─→ AppleKeychainBackend → SecItem* (Apple)
InMemoryKeychain┘                                        ├→ SecretServiceBackend → libsecret (Linux)
                                                         ├→ InMemoryStorageBackend (tests)
                                                         └→ UnsupportedPlatformBackend (everything else)
```

Each backend is the only code that touches its platform's types: `AppleKeychainBackend` owns
`CFDictionary`/`CFTypeRef`, and `SecretServiceBackend` with `CSwiftyChainSecret` owns every
GLib and libsecret pointer. Every other layer works with `Sendable` value types
(`KeychainQuery`, `KeychainAttributes`, `KeychainQueryResult`).

Backends declare `SecureStorageCapabilities`. The engine validates every query against them
before calling the backend, so an option a platform can't honor throws
`KeychainError.platformUnsupported` with the same message everywhere.

## Concurrency Model

`Keychain` is a regular `actor`. Backend calls are synchronous and run on the actor's executor.

- **Apple**: the actor uses the default executor. `SecItem*` calls are brief unless an
  accessibility policy prompts the user.
- **Linux**: the actor runs on `KeychainExecutor`, one serial dispatch queue shared by every
  `Keychain` instance. libsecret calls can block for up to the backend timeout (an unlock
  prompt or a hung daemon), and blocking Swift's cooperative pool would stall unrelated tasks.
- `SecretServiceClient` serializes every libsecret call process-wide with one static lock, so
  the duplicate check and the write in `add` can't interleave with another `Keychain` or
  `KeychainStorage` in the same process. Separate processes still race.

`@KeychainStorage` is synchronous and calls its backend on the caller's thread, bypassing the
actor. Prefer the actor on the main thread, especially on Linux.

## Optional Traits

Two SPM traits gate optional features. Neither is enabled by default.

| Trait | Feature | Swift compile condition |
|-------|---------|------------------------|
| `cryptography` | `kSecClassKey` / `SecKey` storage (Apple only) | `#if Cryptography` |
| `observation` | `AsyncSequence` keychain change stream | `#if Observation` |

Macros (`@KeychainItem`, `@KeychainScope`, `#keychainKey`) are **always included**.

## Platform Notes

All six Apple platforms share the `SecItem*` API. Divergences are handled with `#if os(...)`:

| Divergence | Platforms affected |
|------------|-------------------|
| `whenPasscodeSetThisDeviceOnly` unavailable | tvOS |
| User-presence / biometric protection unavailable | tvOS |
| iCloud Keychain sync (`isSynchronizable`) unavailable | tvOS |
| Access groups require entitlements | iOS, iPadOS, visionOS |
| Multiple keychains, ACLs | macOS only |

Linux uses the freedesktop Secret Service; see the DocC article
[Using SwiftyChain on Linux](Sources/SwiftyChain/Documentation.docc/Articles/Linux.md) for its
differences. Windows, Android, and WebAssembly have no backend yet: `Keychain()` uses
`UnsupportedPlatformBackend`, which throws `platformUnsupported` from every call. A new
platform needs only a new `SecureStorageBackend`; the public API doesn't change.
