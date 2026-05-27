# Testing with SwiftyChain

Test keychain-dependent code without touching the real Apple keychain.

## Overview

SwiftyChain ships a separate `SwiftyChainTesting` product for downstream tests.
It provides two in-memory test doubles:

- `InMemoryKeychain` — for code that depends on ``KeychainProtocol``.
- `InMemoryKeychainBackend` — for code that uses ``KeychainStorage`` directly.

Neither touches the system keychain, so tests run fast and require no entitlements.

## Add the Testing Product

Add `SwiftyChainTesting` to your test target only — never to a shipping target:

```swift
.testTarget(
    name: "MyFeatureTests",
    dependencies: [
        .product(name: "SwiftyChain", package: "SwiftyChain"),
        .product(name: "SwiftyChainTesting", package: "SwiftyChain"),
    ]
)
```

## Test Actor-Based Code

Write your feature code against ``KeychainProtocol``, then pass `InMemoryKeychain`
from tests:

```swift
// Feature code
actor TokenStore {
    private let keychain: any KeychainProtocol
    private let key = KeychainKey<String>(service: "com.example", account: "auth-token")

    init(keychain: any KeychainProtocol) {
        self.keychain = keychain
    }

    func save(token: String) async throws {
        try await keychain.upsert(token, for: key)
    }

    func load() async throws -> String? {
        try await keychain.loadIfPresent(key: key)
    }
}
```

```swift
// Tests
import SwiftyChain
import SwiftyChainTesting
import Testing

@Test func savesAndLoadsToken() async throws {
    let keychain = InMemoryKeychain()
    let store = TokenStore(keychain: keychain)

    try await store.save(token: "secret")

    #expect(try await store.load() == "secret")
}

@Test func loadReturnsNilBeforeFirstSave() async throws {
    let keychain = InMemoryKeychain()
    let store = TokenStore(keychain: keychain)

    #expect(try await store.load() == nil)
}
```

> Tip: Create a new `InMemoryKeychain` instance per test. Each instance starts empty,
> so tests remain isolated even when run in parallel.

## Test Property-Wrapper Code

Use `InMemoryKeychainBackend` when initializing ``KeychainStorage`` in tests:

```swift
import SwiftyChain
import SwiftyChainTesting
import Testing

@Test func storageRoundTrip() {
    let backend = InMemoryKeychainBackend()
    let storage = KeychainStorage<String>(
        "auth-token",
        service: "com.example.app",
        backend: backend
    )

    storage.wrappedValue = "secret"

    #expect(storage.wrappedValue == "secret")
}

@Test func storageReturnsNilWhenEmpty() {
    let backend = InMemoryKeychainBackend()
    let storage = KeychainStorage<String>(
        "auth-token",
        service: "com.example.app",
        backend: backend
    )

    #expect(storage.wrappedValue == nil)
}
```

## Test Macro-Based Code

`@KeychainScope` accepts an optional `keychain:` argument. Pass any
``KeychainProtocol`` expression there — the generated `@KeychainItem`
accessors and `deleteAll()` will use it instead of `Keychain.shared`.

### UI test pattern — environment variable

Because UI tests run in a separate process, the recommended approach is to
define a lazy static on a `Dependencies` type that reads a launch-time
environment variable, then pass it to `@KeychainScope`:

```swift
// AppDependencies.swift — in the app target
import SwiftyChain
import SwiftyChainTesting   // guarded by #if DEBUG

enum AppDependencies {
    static let keychain: any KeychainProtocol = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["USE_MOCK_KEYCHAIN"] == "1" {
            return InMemoryKeychain()
        }
        #endif
        return Keychain.shared
    }()
}

// Secrets.swift
@KeychainScope(service: "com.example.app", keychain: AppDependencies.keychain)
final class Secrets {
    @KeychainItem("api-token")
    var apiToken: String?

    @KeychainItem("refresh-token")
    var refreshToken: String?
}
```

In the UI test target, set the flag before `app.launch()`:

```swift
import XCTest

final class AuthUITests: XCTestCase {
    func testLoginFlowStartsUnauthenticated() {
        let app = XCUIApplication()
        app.launchEnvironment["USE_MOCK_KEYCHAIN"] = "1"
        app.launch()
        // Secrets uses InMemoryKeychain — clean slate, no entitlements needed
    }
}
```

`static let` with a closure is evaluated once, the first time
`AppDependencies.keychain` is accessed. By then `ProcessInfo` is fully
populated, so the environment check is reliable.

### Pre-seeding values for UI tests

An `InMemoryKeychain` starts empty. To simulate a logged-in state, read a
second environment key in the same initializer and call `upsert` before
returning the instance:

```swift
static let keychain: any KeychainProtocol = {
    #if DEBUG
    if ProcessInfo.processInfo.environment["USE_MOCK_KEYCHAIN"] == "1" {
        let mock = InMemoryKeychain()
        if ProcessInfo.processInfo.environment["MOCK_AUTHENTICATED"] == "1" {
            let key = KeychainKey<String>(
                service: "com.example.app",
                account: "api-token"
            )
            try? mock.upsert("test-token", for: key)
        }
        return mock
    }
    #endif
    return Keychain.shared
}()
```

```swift
func testDashboardAppearsWhenAlreadyLoggedIn() {
    let app = XCUIApplication()
    app.launchEnvironment["USE_MOCK_KEYCHAIN"] = "1"
    app.launchEnvironment["MOCK_AUTHENTICATED"] = "1"
    app.launch()
}
```

> Important: Add `SwiftyChainTesting` to the **app target** only when
> building for Debug (`#if DEBUG`). Never let it ship in a Release build.
> A common approach is a conditional SPM dependency or a build-phase check.

## Test Observation (requires `observation` trait)

When the `observation` trait is enabled, `InMemoryKeychain` fully implements
``KeychainProtocol/observeKeychainChanges(service:accessGroup:)``. Events are emitted
synchronously during each mutation, so you can drive and observe changes in the same test:

```swift
// Package.swift — enable the trait in your test target
.testTarget(
    name: "MyFeatureTests",
    dependencies: [
        .product(name: "SwiftyChain", package: "SwiftyChain", traits: ["observation"]),
        .product(name: "SwiftyChainTesting", package: "SwiftyChain", traits: ["observation"]),
    ]
)
```

```swift
import SwiftyChain
import SwiftyChainTesting
import Testing

@Test func emitsEventOnUpsert() async throws {
    let keychain = InMemoryKeychain()
    let key = KeychainKey<String>(service: "com.example", account: "token")
    var events: [KeychainChangeEvent] = []

    let stream = await keychain.observeKeychainChanges(service: "com.example")
    let task = Task {
        for await event in stream { events.append(event) }
    }

    try await keychain.upsert("v1", for: key)
    try await keychain.upsert("v2", for: key)
    task.cancel()

    #expect(events.map(\.kind) == [.saved, .updated])
}
```

## Test Cryptographic Keys (requires `cryptography` trait)

When the `cryptography` trait is enabled, `InMemoryKeychain` implements the crypto-key
CRUD operations:

```swift
// Package.swift — enable the trait in your test target
.testTarget(
    name: "MyFeatureTests",
    dependencies: [
        .product(name: "SwiftyChain", package: "SwiftyChain", traits: ["cryptography"]),
        .product(name: "SwiftyChainTesting", package: "SwiftyChain", traits: ["cryptography"]),
    ]
)
```

```swift
import Security
import SwiftyChain
import SwiftyChainTesting
import Testing

@Test func savesAndLoadsCryptoKey() async throws {
    let keychain = InMemoryKeychain()
    let keyRef = CryptoKeyReference<StoredSecKey>(tag: "com.example.signing-key")
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
    ]
    let secKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil)!
    let storedKey = StoredSecKey(secKey)

    try await keychain.saveCryptoKey(storedKey, for: keyRef)
    let loaded = try await keychain.loadCryptoKey(keyRef: keyRef)

    #expect(loaded.rawValue === secKey)
}
```

## When to Use the Real Keychain

Keep the real ``Keychain`` out of unit tests. Reserve it for narrow integration tests that
specifically validate:

- Keychain entitlements and access groups are configured correctly.
- Items survive process restart (persistence).
- iCloud Keychain sync behavior (`isSynchronizable: true`).
- User-presence-only accessibility (`KeychainAccessibility.whenPasscodeSetThisDeviceOnly`) — items in this class require the device to have a passcode set.

Most feature logic should be covered by in-memory tests, which are faster, deterministic,
and do not accumulate orphaned keychain items across test runs.
