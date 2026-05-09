# SwiftyChain — Specification v1.0

## Overview

A modern, type-safe Swift 6.3 keychain wrapper for Apple platforms. SwiftyChain eliminates unsafe Obj-C-style `CFDictionary`/`OSStatus` interactions, provides full Swift concurrency support via `actor` isolation, and surfaces a clean, ergonomic API across macOS, iOS, iPadOS, tvOS, watchOS, and visionOS.

SwiftyChain provides **two complementary usage modes**:

| Mode | When to use |
|------|-------------|
| **`@KeychainStorage` property wrapper** | Quick, `@AppStorage`-style access on `@MainActor` types. Synchronous reads/writes. Zero boilerplate for common cases. |
| **Swift Macros (`@KeychainItem`, `@KeychainScope`, `#keychainKey`)** | When you need async-native access, compile-time validation of key configuration, or a fully namespaced keychain interface generated from a type declaration. |

---

## Platform Support

### ✅ Apple Platforms (In Scope — v1.0)

| Platform  | Min Version | Notes |
|-----------|------------|-------|
| macOS     | 13.0+      | Full keychain API, ACLs, multiple keychains |
| iOS       | 16.0+      | Sandboxed; shared via access groups |
| iPadOS    | 16.0+      | Same as iOS |
| watchOS   | 9.0+       | Keychain available; limited accessibility options |
| tvOS      | 16.0+      | No user-presence / biometric (no passcode on device) |
| visionOS  | 1.0+       | Full keychain, similar to iOS |

All six Apple platforms support the unified `SecItem*` API (`SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`). Platform-specific divergences (e.g., tvOS has no `userPresence` protection) are handled via `#if os(...)` guards and documented per-API.

### ❌ Windows (Out of Scope — v1.0, Planned for v2.0)

**Why not v1.0:**
- Apple's `Security.framework` (which provides `SecItem*`) does not exist on Windows.
- The Windows equivalent is the **Windows Credential Manager** (`CredWrite`, `CredRead`, `CredDelete`, `CredFree` from `wincred.h`), accessed via Swift's C interop.
- Semantics differ fundamentally: no access groups, no accessibility attributes, no iCloud sync, different item classes, different authentication model.
- Estimated complexity: **2–3× the Apple-only implementation** — effectively a parallel backend.
- Swift on Windows is actively supported (Windows Workgroup announced Jan 2026, Swift 6.3), but no production-grade keychain-equivalent library exists yet.

**How we keep the door open:**
The internal implementation is fronted by a `SecureStorageBackend` protocol. The `AppleKeychainBackend` conforms to it. A future `WindowsCredentialBackend` can be added in v2.0 with `#if os(Windows)` without breaking existing API.

---

## Language & Toolchain

- **Swift**: 6.3
- **Language mode**: `.swift6` (strict concurrency checking, `Sendable` enforcement)
- **Dependencies**: `Security.framework` (Apple SDK, no third-party in core). Optional features (described below) have opt-in dependencies gated by SPM traits.
- **No `@objc` or bridging headers**: All Keychain interaction is via the C-layer Swift overlay of `Security.framework`
- **Formatting**: [Apple swift-format](https://github.com/apple/swift-format) (latest stable, pinned in `Package.swift` as a dev dependency). All source must pass `swift-format lint` before merge. Style config lives in `.swift-format` at the repo root.

### Recommended Implementation Skills

Use these local agent skills while implementing SwiftyChain:

| Skill | Use For | Applies To |
|-------|---------|------------|
| `swift-concurrency` | Actor isolation, `Sendable` correctness, async wrappers around synchronous `SecItem*` calls, strict Swift 6 concurrency issues | `Keychain` actor, `SecureStorageBackend`, observation APIs |
| `swift-concurrency-pro` | Reviewing concurrency-heavy Swift for data races, actor isolation mistakes, and async/await API pitfalls | Final review of core backend and observation code |
| `swift-testing-expert` | Designing Swift Testing suites with `@Test`, `#expect`, parameterized tests, async tests, and coverage strategy | Unit, integration, concurrency, and macro tests |
| `swift-testing-pro` | Writing and reviewing Swift Testing code for maintainability and correctness | `SwiftyChainTests`, `SwiftyChainMacrosTests`, integration tests |
| `swiftui-expert-skill` | Validating SwiftUI-facing APIs, `@Observable` integration, and property-wrapper ergonomics | `@KeychainStorage`, observation trait examples, DocC tutorials |
| `swiftui-pro` | Reviewing SwiftUI usage examples for modern API usage, state ownership, and performance | README examples, DocC tutorials |
| `spm-build-analysis` | Reviewing Swift Package layout, target graph, macro target dependencies, SPM traits, and build overhead | `Package.swift`, macro target, trait-gated features |
| `xcode-build-benchmark` | Measuring clean and incremental build performance once the package has enough implementation to benchmark | Pre-release build performance baseline |
| `xcode-project-analyzer` | Auditing Xcode scheme behavior, simulator builds, CI destinations, and project-level build configuration | Cross-platform CI and Xcode integration |
| `apple-appstore-reviewer` | Checking Apple-platform security, privacy, entitlement, and App Store risk areas before release | Keychain access groups, biometric/user-presence APIs, documentation |

### Optional Features via SPM Traits

SwiftyChain uses [Swift Package Manager traits](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0425-package-traits.md) (SPM 6.1+) to gate optional features. Consumers declare traits in `Package.swift` to opt in; disabling a trait removes its dependencies and compiled code.

| Trait | Feature | Dependencies | Size Impact | Use When |
|-------|---------|--------------|-------------|----------|
| `default` | Core (CRUD, `@KeychainStorage`) | `Security.framework` only | ~100 KB | Always included; base functionality |
| `macros` | Swift Macros (`@KeychainItem`, `@KeychainScope`, `#keychainKey`) | `swift-syntax` (pre-built binary) | +50 KB | Need compile-time validation or async accessors |
| `cryptography` | `kSecClassKey` support (cryptographic key storage) | `Security.framework` | +30 KB | Store `SecKey` objects; use with signing/verification |
| `observation` | `AsyncSequence`-based observation + `@Observable` integration | Foundation (stdlib) | +20 KB | React to keychain changes in real-time |

**Example usage in a consuming `Package.swift`:**

```swift
.package(url: "https://github.com/manman-swift/SwiftyChain.git", from: "1.0.0"),

.target(name: "MyApp", dependencies: [
    .product(name: "SwiftyChain", package: "SwiftyChain", traits: ["macros", "observation"])
])
```

**Compile-condition naming**: per [SE-0450](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-package-traits.md), each enabled trait becomes a Swift compile-condition with the same name. Source code therefore guards optional features with `#if Cryptography` / `#if Observation` (not custom `SWIFTCHAIN_*` macros).

**Rationale**: Core keychain usage is lightweight (passwords, tokens). Advanced users who need macros, cryptography, or real-time observation can opt in; others stay minimal.

---

## Architecture

### Module Layout (Swift Package)

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
│   └── SwiftyChainMacros/                       # Macro implementation target (separate executable)
│       ├── KeychainItemMacro.swift              # @KeychainItem attached accessor macro
│       ├── KeychainScopeMacro.swift             # @KeychainScope attached member+peer macro
│       ├── KeychainKeyMacro.swift               # #keychainKey freestanding expression macro
│       └── SwiftyChainMacrosPlugin.swift        # CompilerPlugin entry point
└── Tests/
    ├── SwiftyChainTests/
    │   ├── KeychainTests.swift
    │   ├── KeychainStorableTests.swift
    │   └── Mocks/
    │       └── MockKeychainBackend.swift
    └── SwiftyChainMacrosTests/
        ├── KeychainItemMacroTests.swift
        ├── KeychainScopeMacroTests.swift
        └── KeychainKeyMacroTests.swift
```

**Package targets in `Package.swift`:**

```swift
// SwiftyChain — library (depends on SwiftyChainMacros for re-exporting macro declarations)
.target(name: "SwiftyChain", dependencies: [
    .target(name: "SwiftyChainMacros")
]),
// SwiftyChainMacros — compiler plugin executable
.macro(name: "SwiftyChainMacros", dependencies: [
    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
]),
```

---

## Core Types

### `KeychainError`

```swift
public enum KeychainError: Error, Sendable {
    case itemNotFound
    case duplicateItem
    case authenticationFailed           // user cancelled biometric / passcode
    case userPresenceRequired           // item requires authentication
    case unexpectedData                 // data from keychain couldn't be decoded
    case encodingFailed(any Error)
    case decodingFailed(any Error)
    case operationFailed(OSStatus)      // raw SecItem status for unhandled codes
    case accessGroupDenied
    case platformUnsupported(String)    // e.g., userPresence on tvOS
}
```

### `KeychainAccessibility`

Maps 1:1 to `kSecAttrAccessible*` constants, filtered by platform:

```swift
public enum KeychainAccessibility: Sendable, Hashable {
    case afterFirstUnlock               // available on all platforms
    case afterFirstUnlockThisDeviceOnly
    case whenUnlocked                   // default
    case whenUnlockedThisDeviceOnly
    case whenPasscodeSetThisDeviceOnly  // unavailable on tvOS
}
```

### `KeychainStorable` Protocol

```swift
public protocol KeychainStorable: Sendable {
    func keychainData() throws -> Data
    static func fromKeychainData(_ data: Data) throws -> Self
}
```

**Built-in conformances** (no boilerplate for consumers):
- `String` (UTF-8)
- `Data` (passthrough)
- `Bool`, `Int`, `Double` (little-endian binary)
- Any `T: Codable & Sendable` via a `CodableKeychainStorable` wrapper. The default encoder is `PropertyListEncoder` with `outputFormat = .binary` — chosen for compactness and deterministic output, both of which matter when the same payload is round-tripped through `kSecValueData`. Consumers can opt into JSON via an explicit wrapper if they need it.

### `KeychainKey<Value>`

Generic, `Sendable`, `Hashable` key descriptor:

```swift
public struct KeychainKey<Value: KeychainStorable>: Sendable, Hashable {
    public let service: String
    public let account: String
    public let accessGroup: String?             // nil = default keychain group
    public let accessibility: KeychainAccessibility
    public let isSynchronizable: Bool           // iCloud Keychain sync
    public let label: String?                   // human-readable label
    public let comment: String?

    public init(
        service: String,
        account: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked,
        isSynchronizable: Bool = false,
        label: String? = nil,
        comment: String? = nil
    )
}
```

### `KeychainItemClass`

Represents the modern `kSecClass*` values:

```swift
public enum KeychainItemClass: Sendable {
    case genericPassword       // kSecClassGenericPassword (default)
    case internetPassword      // kSecClassInternetPassword — adds server/port/protocol
    #if Cryptography
    case cryptographicKey      // kSecClassKey — wraps SecKey (trait: "cryptography")
    #endif
}
```

v1.0 includes `genericPassword` and `internetPassword` by default. The `cryptography` trait adds `cryptographicKey` support.

---

## Public API — `Keychain` Actor

```swift
public actor Keychain {

    public static let shared = Keychain()

    /// Default initializer used by `shared`; wires up the Apple `SecItem*` backend.
    public init() { /* ... */ }

    /// Test-only initializer that lets unit tests inject a mock backend.
    /// Exposed to test targets via `@testable import SwiftyChain`.
    internal init(backend: any SecureStorageBackend)

    // CRUD
    public func save<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws
    public func load<T: KeychainStorable>(key: KeychainKey<T>) throws -> T
    public func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T?
    public func update<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws
    public func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws  // save or update
    public func delete<T: KeychainStorable>(key: KeychainKey<T>) throws

    // Bulk deletion
    public func deleteAll(service: String, accessGroup: String? = nil) throws
    public func deleteAllSynchronizable(service: String, accessGroup: String? = nil) throws
    public func deleteAllItems(matching query: KeychainDeleteQuery) throws

    // Query
    public func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool
    public func allAccounts(service: String, accessGroup: String? = nil) throws -> [String]

    #if Cryptography
    // Cryptographic key storage (trait: "cryptography")
    public func saveCryptoKey<T: CryptoKeyStorable>(_ key: T, for keyRef: CryptoKeyReference<T>) throws
    public func loadCryptoKey<T: CryptoKeyStorable>(keyRef: CryptoKeyReference<T>) throws -> T
    #endif

    #if Observation
    // Keychain observation (trait: "observation")
    public func observeKeychainChanges(
        service: String,
        accessGroup: String? = nil
    ) -> some AsyncSequence<KeychainChangeEvent, Never>   // concrete impl is an `AsyncStream`
    #endif
}
```

**Concurrency note**: `Keychain` is a regular `actor` (not a `@globalActor`); all calls require `await`. Internally, `SecItem*` functions are synchronous C calls — they are wrapped in a continuation that dispatches off the main thread to avoid blocking UI.

### Bulk Deletion — Sign-Out & Data Erasure

A first-class use case for `deleteAll` is clearing all app secrets on sign-out or when a user requests data deletion (GDPR/privacy requirement).

```swift
/// Filter structure for flexible bulk deletion.
public struct KeychainDeleteQuery: Sendable {
    public let service: String?
    public let accessGroup: String?
    public let includeSynchronizable: Bool   // default: true (deletes both local + iCloud)
    public let itemClass: KeychainItemClass  // default: .genericPassword

    public static func allItems(
        service: String,
        accessGroup: String? = nil
    ) -> KeychainDeleteQuery
}
```

**Common sign-out pattern:**

```swift
// Delete everything for this service (local + iCloud-synced):
try await Keychain.shared.deleteAll(service: "com.example.app")

// Delete only iCloud-synced items (e.g., shared group, keep local device data):
try await Keychain.shared.deleteAllSynchronizable(service: "com.example.app")

// Full custom query:
try await Keychain.shared.deleteAllItems(matching:
    .init(service: "com.example.app", accessGroup: "group.com.example", includeSynchronizable: true)
)
```

**Security note**: `deleteAll` is intentionally not callable from `@KeychainStorage` or the macros — it is a deliberate, explicit actor call to prevent accidental data loss.

### Internet Password Extension

```swift
public struct InternetPasswordKey: Sendable, Hashable {
    public let server: String
    public let account: String
    public let port: Int?
    public let path: String?
    public let `protocol`: InternetProtocol
    public let authenticationType: AuthenticationType
    public let accessGroup: String?
    public let accessibility: KeychainAccessibility
}

extension Keychain {
    public func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws
    public func loadInternetPassword(for key: InternetPasswordKey) throws -> String
    public func deleteInternetPassword(for key: InternetPasswordKey) throws
}
```

---

## `@KeychainStorage` Property Wrapper

Mirrors the ergonomics of `@AppStorage`:

```swift
@KeychainStorage("auth_token", service: "com.example.app")
var authToken: String?

// With access group (shared keychain):
@KeychainStorage("session_id", service: "com.example.app", accessGroup: "group.com.example")
var sessionId: String?
```

Semantics & constraints:
- Reads and writes are **synchronous**. The wrapper holds its own reference to the shared `AppleKeychainBackend` and calls `SecItem*` directly — it does **not** route through the `Keychain` actor (an actor cannot be called synchronously from non-isolated code).
- This is safe because Apple's `SecItem*` API is thread-safe and the calls are brief; the wrapper is intended to be used from `@MainActor`-isolated types (e.g., `@Observable` view models) where a quick keychain hit is comparable in cost to a UserDefaults read.
- `Value` must be `KeychainStorable` and either `Optional` or `ExpressibleByNilLiteral` (so a missing item maps to `nil` without throwing).
- Errors raised by the backend are surfaced via a separate `projectedValue` (`$authToken: KeychainError?`) rather than crashing — see the DocC reference for the recovery pattern.
- **Not appropriate for items that require user presence / biometric prompts.** Those items can block the calling thread on a UI prompt; use the async `Keychain` actor API for them instead.

---

## Swift Macros

Macros ship in the `SwiftyChainMacros` compiler plugin and are re-exported from the main `SwiftyChain` module — consumers only need `import SwiftyChain`.

### Why macros over property wrappers alone?

| Capability | `@KeychainStorage` (wrapper) | Macros |
|---|---|---|
| Async `get`/`set` accessors | ❌ wrappers can't expose `async` accessors | ✅ generated via `@attached(accessor)` |
| Compile-time key validation | ❌ runtime errors only | ✅ compiler errors / warnings at call site |
| Incompatible flag detection | ❌ | ✅ e.g. `isSynchronizable + ThisDeviceOnly` emits error |
| Platform-specific guard | ❌ | ✅ `whenPasscodeSetThisDeviceOnly` on tvOS = compiler warning |
| Namespaced keychain types | ❌ | ✅ `@KeychainScope` generates full typed namespace |
| Zero-boilerplate key constants | ❌ manual `KeychainKey` init | ✅ `#keychainKey(...)` infers `Value` type |

---

### `#keychainKey` — Freestanding Expression Macro

Creates a compile-time validated `KeychainKey<Value>`. The macro role is `@freestanding(expression)`.

```swift
// Type is inferred from usage context:
let tokenKey: KeychainKey<String> = #keychainKey(
    service: "com.example.app",
    account: "auth_token"
)

// With options:
let syncedKey: KeychainKey<Data> = #keychainKey(
    service: "com.example.app",
    account: "sync_payload",
    accessibility: .afterFirstUnlock,
    isSynchronizable: true           // ✅ compatible with .afterFirstUnlock
)

// Compile-time error examples:
let bad1: KeychainKey<String> = #keychainKey(
    service: "",                     // ❌ error: service must be a non-empty string literal
    account: "token"
)
let bad2: KeychainKey<String> = #keychainKey(
    service: "com.example.app",
    account: "token",
    accessibility: .whenUnlockedThisDeviceOnly,
    isSynchronizable: true           // ❌ error: 'ThisDeviceOnly' and isSynchronizable are mutually exclusive
)
```

**Validation performed at compile time:**
- `service` and `account` are non-empty string literals (not variables)
- `isSynchronizable: true` is mutually exclusive with any `ThisDeviceOnly` accessibility case
- `accessGroup` is a non-empty string literal when provided

**Platform diagnostic** (warning, not error — targets may be multi-platform):
- `accessibility: .whenPasscodeSetThisDeviceOnly` emits `#warning`-equivalent when the active SDK is tvOS

---

### `@KeychainItem` — Attached Accessor Macro

Role: `@attached(accessor)`. Applied to a stored `var` declaration inside a type. Generates `async get` and `async set` accessors that interact with `Keychain.shared`.

```swift
struct AuthStore {
    @KeychainItem(service: "com.example.app", account: "auth_token")
    var authToken: String?

    @KeychainItem(
        service: "com.example.app",
        account: "refresh_token",
        accessibility: .afterFirstUnlock,
        isSynchronizable: true
    )
    var refreshToken: String?
}

// Generated (illustrative — not written by hand):
// extension AuthStore {
//     var authToken: String? {
//         get async throws { try await Keychain.shared.loadIfPresent(key: Self._authTokenKey) }
//     }
//     func setAuthToken(_ newValue: String?) async throws {
//         if let newValue {
//             try await Keychain.shared.upsert(newValue, for: Self._authTokenKey)
//         } else {
//             try await Keychain.shared.delete(key: Self._authTokenKey)
//         }
//     }
//     fileprivate static let _authTokenKey = KeychainKey<String>(
//         service: "com.example.app", account: "auth_token"
//     )
// }

// Usage:
let token = try await store.authToken
try await store.setAuthToken("eyJ...")
try await store.setAuthToken(nil)   // deletes
```

**Generated by the macro:**
1. A computed property with a `get async throws` accessor that calls `Keychain.shared.loadIfPresent(key:)` for `Optional` values, or `load(key:)` for non-optional. (Swift does not support `async throws` setters on stored or computed properties, so writes are exposed as a method instead.)
2. A companion method `func set<VarName>(_ newValue: T) async throws` that calls `Keychain.shared.upsert(_:for:)` when the new value is non-nil and `delete(key:)` when it is `nil`.
3. A `fileprivate static let _<varName>Key: KeychainKey<T>` peer constant (companion to the accessor).

**Macro diagnostics:**
- `account` must be a string literal (not a variable) — compile error otherwise
- Property type must conform to `KeychainStorable` — compile error with fix-it suggestion to add conformance
- Warns if applied to a `let` (should be `var`)

---

### `@KeychainScope` — Attached Member + Peer Macro

Role: `@attached(member) @attached(peer)`. Applied to a `struct` (or `final class`) to generate a fully namespaced, type-safe keychain interface. All `@KeychainItem`-annotated members within the scope inherit the scope's `service` and `accessGroup`.

```swift
@KeychainScope(service: "com.example.app", accessGroup: "group.com.example")
struct AppKeychain {
    @KeychainItem(account: "auth_token")
    var authToken: String?

    @KeychainItem(account: "device_id", accessibility: .afterFirstUnlockThisDeviceOnly)
    var deviceId: String?

    @KeychainItem(account: "user_prefs", isSynchronizable: true)
    var userPreferences: UserPreferences?  // UserPreferences: Codable & Sendable
}

// Usage:
let keychain = AppKeychain()
let token = try await keychain.authToken
try await keychain.setAuthToken("eyJ...")
```

**What `@KeychainScope` generates:**
1. Processes each `@KeychainItem` member and injects the scope's `service` and `accessGroup` into the generated `KeychainKey`. Per-member `service` and `accessGroup` are **not allowed** — the scope is, by definition, a single namespace, and allowing per-member overrides would silently produce items in a different namespace than the type name implies.
2. Generates a `static let shared = AppKeychain()` singleton convenience if the type has no stored properties other than keychain items.
3. Generates a `deleteAll() async throws` method that removes all items in the scope's service+accessGroup.

**Macro diagnostics:**
- Scope-level `service` must be a non-empty string literal — compile error.
- Member-level `@KeychainItem(service: …)` or `@KeychainItem(accessGroup: …)` inside a `@KeychainScope` type — compile error with a fix-it that removes the redundant argument.
- Non-`@KeychainItem` stored properties inside a `@KeychainScope` type emit a warning (the scope is intended to be a pure keychain namespace).
- Per-member `accessibility`, `isSynchronizable`, `label`, `comment`, and `account` are still permitted and override / extend the scope defaults as expected.

---

## `SecureStorageBackend` Protocol (Internal)

Enables mock injection in tests and future Windows/Linux backends. The protocol is expressed in Swift-native, `Sendable` value types — `CFDictionary` and `CFTypeRef` are deliberately kept out of the protocol surface because they are not `Sendable` and would block `actor`-based isolation.

```swift
/// Sendable description of a keychain query. Translated to a `CFDictionary`
/// inside `AppleKeychainBackend`; mocks read it as a plain Swift struct.
internal struct KeychainQuery: Sendable, Hashable {
    let itemClass: KeychainItemClass
    let service: String?
    let account: String?
    let accessGroup: String?
    let accessibility: KeychainAccessibility?
    let isSynchronizable: Bool?
    let returnData: Bool
    let returnAttributes: Bool
    let matchLimit: MatchLimit              // .one / .all
}

/// Sendable description of attributes to apply on update.
internal struct KeychainAttributes: Sendable, Hashable {
    let data: Data?
    let label: String?
    let comment: String?
    let accessibility: KeychainAccessibility?
}

/// Sendable result of a `copyMatching` call.
internal enum KeychainQueryResult: Sendable {
    case data(Data)
    case attributes([KeychainAttribute])
    case items([KeychainQueryResult])       // for matchLimit == .all
}

internal protocol SecureStorageBackend: Sendable {
    func add(_ query: KeychainQuery, data: Data) throws
    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult
    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws
    func delete(matching query: KeychainQuery) throws
}

internal struct AppleKeychainBackend: SecureStorageBackend { ... }
```

**Translation boundary**: `AppleKeychainBackend` is the only place in the codebase that bridges between the Swift `KeychainQuery`/`KeychainAttributes` value types and Apple's `CFDictionary` representation. Every other layer — actor, property wrapper, macros, mocks — sees only `Sendable` Swift types. This keeps strict-concurrency checking happy and makes the future `WindowsCredentialBackend` straightforward to drop in.

---

## Security Requirements

1. **No in-memory caching of secrets** — every read hits the keychain.
2. **Zeroing on deallocation** — `Data` containing secret material is zeroed before deallocation where the OS doesn't guarantee it.
3. **No logging of values** — errors may log `OSStatus` codes but never the secret value or its `Data` representation.
4. **Strict Sendable** — no shared mutable state outside the `Keychain` actor isolation.
5. **Access control** — `KeychainAccessibility` is always set explicitly; no silent fallback to insecure defaults.
6. **No force unwrap** — all `CFTypeRef` casts use `as?` with typed error throws.

---

## Testing Strategy

- **Unit tests**: Use `MockKeychainBackend` (in-memory dictionary) injected via the `internal init(backend:)` on `Keychain`. Test targets reach this initializer with `@testable import SwiftyChain`; production callers see only the public `init()` and `Keychain.shared`.
- **Integration tests**: Separate test target that runs against the real keychain (requires entitlements; CI runs on macOS runner with keychain access).
- **Swift Testing** (`@Test`, `#expect`, `#require`) throughout — no XCTest.
- **Parameterized tests** for all `KeychainStorable` built-in conformances.
- **Concurrency tests** using `withTaskGroup` to validate actor isolation under concurrent access.
- **Macro expansion tests** (`SwiftyChainMacrosTests` target): Use `swift-syntax`'s `assertMacroExpansion` to verify that each macro produces exactly the expected source expansion and emits the correct diagnostics for invalid inputs. These run offline with no keychain access needed.
- **Bulk deletion tests**: Verify `deleteAll`, `deleteAllSynchronizable`, and `deleteAllItems(matching:)` against `MockKeychainBackend` seeded with items across multiple accounts.

### Coverage Targets

| Target | Minimum line coverage |
|--------|----------------------|
| `SwiftyChain` (core + backend) | ≥ 90% |
| `SwiftyChainMacros` (macro expansions) | ≥ 85% |
| Property wrapper + extensions | ≥ 90% |
| Overall | ≥ 88% |

Coverage is measured via `swift test --enable-code-coverage` + `llvm-cov export`. The CI workflow uploads an LCOV report as an artifact and fails the build if the overall threshold is not met.

### Running Tests Locally

```bash
# All unit + macro tests (no keychain entitlement needed):
swift test --filter SwiftyChainTests
swift test --filter SwiftyChainMacrosTests

# Integration tests (macOS only, requires keychain entitlement):
swift test --filter SwiftyChainIntegrationTests

# With code coverage:
swift test --enable-code-coverage
llvm-cov report \
  .build/debug/SwiftyChainPackageTests.xctest/Contents/MacOS/SwiftyChainPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  --ignore-filename-regex='.build|Tests'
```

---

---

## Documentation

### DocC

Every public symbol carries a DocC comment with:
- One-sentence summary
- `Parameters` and `Returns` sections for all non-trivial functions
- `Throws` section listing every `KeychainError` case that can be raised
- `Note` or `Warning` callouts for platform-specific behaviour (e.g., tvOS restrictions)
- At least one `## Example` code snippet per type and per non-trivial method

### DocC Tutorials

A dedicated `Tutorials/` folder inside `Sources/SwiftyChain/Documentation.docc/` contains the following step-by-step tutorials:

| Tutorial | Trait | What it teaches |
|----------|-------|----------------|
| **Getting Started** | core | Add SwiftyChain via SPM; save and load a `String` password using the `Keychain` actor directly |
| **Property Wrapper Basics** | core | Use `@KeychainStorage` in a SwiftUI `@Observable` view model; handle `nil` and sign-in/sign-out |
| **Macro-Driven Keychain** | `macros` | Define a `@KeychainScope` struct; use `@KeychainItem` for async accessors; use `#keychainKey` for static key constants |
| **Shared Keychain with Access Groups** | core | Configure app groups; share a session token between an app and its extension |
| **Sign-Out & Data Erasure** | core | Call `deleteAll` on sign-out; handle iCloud-synced vs. device-only items separately |
| **Cryptographic Keys** | `cryptography` | Generate, store, and retrieve a `SecKey` using `CryptoKeyReference`; sign and verify a payload |
| **Observing Keychain Changes** | `observation` | Subscribe to `observeKeychainChanges(...)`; drive an `@Observable` view model from the stream; handle teardown |

Tutorials are rendered by the DocC compiler and hosted on the project's GitHub Pages site via the CI workflow.

---

## Contribution Guide

> Lives in `CONTRIBUTING.md` at the repo root.

### Prerequisites

```bash
# Install Swift 6.3 via swiftly:
swiftly install 6.3
swiftly use 6.3

# Verify:
swift --version  # Should print 6.3.x
```

### Fork & Branch

```bash
git clone https://github.com/<your-fork>/SwiftyChain.git
cd SwiftyChain
git checkout -b feature/<short-description>
```

### Build

```bash
swift build
```

### Lint (must pass before opening a PR)

```bash
swift-format lint --recursive Sources Tests
# Auto-fix (review changes before committing):
swift-format format --recursive --in-place Sources Tests
```

### Test

```bash
# Fast (no keychain access needed):
swift test --filter SwiftyChainTests
swift test --filter SwiftyChainMacrosTests

# Full suite with coverage:
swift test --enable-code-coverage
```

### Submitting a PR

1. Ensure `swift-format lint` passes with zero violations.
2. Ensure all existing tests pass.
3. Add tests for any new behaviour — coverage must not drop below the thresholds in the Testing Strategy section.
4. Update DocC comments for any changed public API.
5. Open a PR against `main`; the CI workflow will run automatically.

### Code of Conduct

This project follows the [Swift Code of Conduct](https://www.swift.org/code-of-conduct/).

---

## GitHub CI

Two workflow files live in `.github/workflows/`.

### `ci.yml` — runs on every PR and push to `main`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: swift-format lint
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Install swift-format
        run: brew install swift-format
      - name: Lint
        run: swift-format lint --recursive --strict Sources Tests

  # macOS leg: full `swift test` + coverage + threshold enforcement.
  # The macOS runner builds the Swift Package directly; this is the canonical CI signal.
  build-test-macos:
    name: Build & Test (macOS)
    runs-on: macos-15   # ships Xcode 16.x with Swift 6.3
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: swift build -c debug

      - name: Unit & Macro Tests (no keychain)
        run: |
          swift test \
            --filter SwiftyChainTests \
            --filter SwiftyChainMacrosTests \
            --enable-code-coverage

      - name: Integration Tests
        run: swift test --filter SwiftyChainIntegrationTests

      - name: Generate coverage report
        run: |
          xcrun llvm-cov export \
            .build/debug/SwiftyChainPackageTests.xctest/Contents/MacOS/SwiftyChainPackageTests \
            -instr-profile .build/debug/codecov/default.profdata \
            -format=lcov \
            --ignore-filename-regex='.build|Tests' \
            > coverage.lcov

      - name: Upload coverage
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage.lcov
          retention-days: 14

      - name: Enforce coverage threshold
        run: |
          COVERAGE=$(xcrun llvm-cov report \
            .build/debug/SwiftyChainPackageTests.xctest/Contents/MacOS/SwiftyChainPackageTests \
            -instr-profile .build/debug/codecov/default.profdata \
            --ignore-filename-regex='.build|Tests' \
            | awk '/TOTAL/{print $NF}' | tr -d '%')
          echo "Total coverage: ${COVERAGE}%"
          python3 -c "import sys; sys.exit(0 if float('${COVERAGE}') >= 88 else 1)"

  # Cross-platform leg: confirm the package compiles on every supported Apple platform.
  # iOS Simulator gets a real `xcodebuild test` run; tvOS/watchOS/visionOS are
  # build-only because the simulator keychain semantics diverge enough that
  # platform-specific test plans are tracked separately. All four legs run on
  # the macOS runner via the bundled simulator destinations.
  build-other-platforms:
    name: Build (${{ matrix.platform.name }})
    runs-on: macos-15
    strategy:
      fail-fast: false
      matrix:
        platform:
          - name: iOS
            destination: "platform=iOS Simulator,name=iPhone 15"
            run-tests: true
          - name: tvOS
            destination: "platform=tvOS Simulator,name=Apple TV"
            run-tests: false
          - name: watchOS
            destination: "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)"
            run-tests: false
          - name: visionOS
            destination: "platform=visionOS Simulator,name=Apple Vision Pro"
            run-tests: false
    steps:
      - uses: actions/checkout@v4

      - name: Build for ${{ matrix.platform.name }}
        run: |
          xcodebuild build \
            -scheme SwiftyChain \
            -destination '${{ matrix.platform.destination }}' \
            -skipPackagePluginValidation

      - name: Test on ${{ matrix.platform.name }}
        if: matrix.platform.run-tests
        run: |
          xcodebuild test \
            -scheme SwiftyChain \
            -destination '${{ matrix.platform.destination }}' \
            -skipPackagePluginValidation

  docc:
    name: Build DocC
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Build documentation
        run: |
          swift package generate-documentation \
            --target SwiftyChain \
            --disable-indexing \
            --warnings-as-errors
```

### `pages.yml` — deploys DocC to GitHub Pages on push to `main`

```yaml
name: Deploy Docs

on:
  push:
    branches: [main]

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  deploy:
    runs-on: macos-15
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - name: Build DocC site
        run: |
          swift package \
            --allow-writing-to-directory ./docs \
            generate-documentation \
            --target SwiftyChain \
            --output-path ./docs \
            --transform-for-static-hosting \
            --hosting-base-path SwiftyChain
      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./docs
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

**Action versions used (pinned to latest stable major as of May 2026):**

| Action | Version |
|--------|---------|
| `actions/checkout` | `v4` |
| `actions/upload-artifact` | `v4` |
| `actions/upload-pages-artifact` | `v3` |
| `actions/deploy-pages` | `v4` |

---

## License

MIT License. `LICENSE` file at repo root:

```
MIT License

Copyright (c) 2026 SwiftyChain Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Deliverables

| # | Deliverable | Notes |
|---|-------------|-------|
| 1 | `Package.swift` | Swift 6.3, all Apple platforms |
| 2 | `KeychainError`, `KeychainAccessibility`, `KeychainItemClass` | Core enums |
| 3 | `KeychainStorable` protocol + built-in conformances | `String`, `Data`, `Bool`, `Int`, `Double`, `Codable` |
| 4 | `KeychainKey<Value>` | Generic, Sendable, Hashable |
| 5 | `SecureStorageBackend` + `AppleKeychainBackend` | Internal SecItem* bridge |
| 6 | `Keychain` actor | CRUD + query + bulk delete |
| 7 | `KeychainDeleteQuery` + sign-out API | `deleteAll`, `deleteAllSynchronizable`, `deleteAllItems(matching:)` |
| 8 | Internet password support | `InternetPasswordKey` + extensions |
| 9 | `@KeychainStorage` property wrapper | Synchronous, `@MainActor`-safe |
| 10 | `#keychainKey` freestanding macro (trait: `macros`) | Compile-time validated `KeychainKey` construction |
| 11 | `@KeychainItem` attached accessor macro (trait: `macros`) | Async get/set + peer key constant |
| 12 | `@KeychainScope` attached member macro (trait: `macros`) | Namespaced type-safe keychain interface |
| 13 | `SwiftyChainMacrosPlugin.swift` | `CompilerPlugin` entry point |
| 14 | Cryptographic key storage (trait: `cryptography`) | `CryptoKeyStorable`, `CryptoKeyReference`, `SecKey` wrapper |
| 15 | `AsyncSequence`-based observation (trait: `observation`) | `observeKeychainChanges()` — real-time keychain change stream |
| 16 | `@Observable` integration (trait: `observation`) | Macro for reactive keychain binding |
| 17 | `MockKeychainBackend` + unit tests | Swift Testing, ≥ 90% coverage |
| 18 | Macro expansion tests (`assertMacroExpansion`) | Offline, no keychain entitlement needed |
| 19 | Integration test target | Real keychain, macOS CI |
| 20 | `.swift-format` config + CI lint step | Apple swift-format, zero violations required |
| 21 | `.github/workflows/ci.yml` | PR gate: lint + build + test + coverage threshold |
| 22 | `.github/workflows/pages.yml` | DocC deploy to GitHub Pages on merge to `main` |
| 23 | DocC API documentation | All public symbols, ≥ 1 example each |
| 24 | DocC tutorials (7) | Getting Started, Property Wrapper, Macros, Access Groups, Sign-Out, Crypto Keys, Observation |
| 25 | `CONTRIBUTING.md` | Build, lint, test, PR instructions |
| 26 | `LICENSE` | MIT |
| 27 | `README.md` | Quick-start, both usage modes, trait selection guide, badges |

---

## Out of Scope (v1.0+)

### Primary Rationale

**v1.0 ships with core password/token storage + optional traits** for specialized use cases. This keeps the base library lightweight while offering advanced features for users who need them. `AsyncSequence` observation, cryptographic keys, and compile-time macros are built-in as opt-in traits, not deferred.

### Out-of-Scope Details

- **Windows / Linux support** (see rationale earlier in spec; planned v2.0)

- **`kSecClassCertificate` / `kSecClassIdentity`** — pending user demand, may be added in v1.1+
  - Certificates and identities require parsing, chain validation, and trust evaluation.
  - Less commonly used in typical app workflows (more common in enterprise / VPN / client-certificate scenarios).
  - **Decision**: v1.0 ships without these; if users request certificate support, v1.1 will offer support (likely as optional feature).
  - Not included by default to avoid API bloat for the 90% of users who only need passwords/tokens.

- **Keychain migration / versioning utilities** — planned v1.1 or later (post-launch feedback)
  - Refers to utilities for bulk-migrating items between services, renaming accounts, or transforming stored data format when an app evolves.
  - Example: if you shipped v1 storing passwords under `service: "com.example"` and v2 wants to migrate to `service: "com.example.v2"` with a new encryption scheme.
  - These are *convenience layers* on top of the core CRUD API; developers can implement migration manually if needed in v1.0.
  - v1.1 will offer `migrate(from:to:transform:)` builder patterns and best-practice templates (as needed based on user feedback).

- **macOS-only legacy keychain APIs** (`SecKeychainCreate`, `SecKeychainItemCopyAttributesAndData`, ACLs) — use `SecItem*` uniformly
  - These APIs are macOS-only and rarely used in modern iOS/Swift development.
  - The unified `SecItem*` API is the modern, cross-platform standard.
  - Supporting both would fragment the API and create a larger maintenance surface.

- **Codecov.io or Coveralls integration** — LCOV artifact + threshold enforcement in CI is sufficient for v1.0
  - v1.0's CI uploads LCOV reports as build artifacts and enforces thresholds locally.
  - Third-party coverage services (Codecov, Coveralls) can be integrated in v1.1 if needed.
  - Avoids external dependencies and service coupling for the initial release.
