# SwiftyChain

[![CI](https://img.shields.io/github/actions/workflow/status/maniramezan/SwiftyChain/ci.yml?branch=main&label=CI&logo=github)](https://github.com/maniramezan/SwiftyChain/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-GitHub_Pages-0969da?logo=github)](https://maniramezan.github.io/SwiftyChain/)
[![Swift](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2018%20%7C%20macOS%2015%20%7C%20tvOS%2018%20%7C%20watchOS%2011%20%7C%20visionOS%202%20%7C%20Linux-blue)](https://github.com/maniramezan/SwiftyChain/blob/main/Package.swift)
[![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen?logo=swift&logoColor=white)](https://swift.org/package-manager)
[![License](https://img.shields.io/badge/license-MIT-brightgreen)](LICENSE)

SwiftyChain is a Swift 6.3 keychain wrapper for Apple platforms and Linux. It provides a typed `Keychain` actor for async-safe access and an `@KeychainStorage` property wrapper for simple optional values. The same code stores secrets in the Apple Keychain or, on Linux, in the Secret Service (GNOME Keyring or KWallet).

## Installation

Add SwiftyChain to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/maniramezan/SwiftyChain", from: "2.0.0"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "SwiftyChain", package: "SwiftyChain"),
        ]
    ),
]
```

## Quick Start

```swift
import SwiftyChain

let tokenKey = KeychainKey<String>(service: "com.example.app", account: "auth_token")
try await Keychain.shared.upsert("secret", for: tokenKey)
let token = try await Keychain.shared.loadIfPresent(key: tokenKey)
```

```swift
@KeychainStorage("auth_token", service: "com.example.app")
var authToken: String?
```

`account` and `service` are the required initializer parameters. The full
initializer is:

```swift
@KeychainStorage(
    "auth_token",
    service: "com.example.app",
    accessGroup: nil,
    accessibility: .whenUnlocked,
    isSynchronizable: false
)
var authToken: String?
```

Use the optional arguments only when needed:

- `accessGroup` to share credentials with another app target or extension
- `accessibility` to control when the item can be read
- `isSynchronizable` to opt into iCloud Keychain sync

## Platform Support

| Platform  | Min Version |
|-----------|------------|
| macOS     | 15.0+      |
| iOS       | 18.0+      |
| iPadOS    | 18.0+      |
| watchOS   | 11.0+      |
| tvOS      | 18.0+      |
| visionOS  | 2.0+       |
| Linux     | Any distribution with Swift 6.3+; libsecret 0.19+ at runtime |

> **tvOS note**: `whenPasscodeSetThisDeviceOnly` accessibility is unavailable on tvOS. The `#keychainKey` macro emits a warning if you use it on that platform.

### Linux

On Linux, `Keychain.shared` and `@KeychainStorage` store secrets in the freedesktop
Secret Service through libsecret. Nothing extra is needed to build. At runtime the
machine needs:

- libsecret (`libsecret-1-0` on Debian and Ubuntu, `libsecret` on Fedora), and
- a D-Bus session with a Secret Service provider, such as GNOME Keyring or KWallet.

If any of these is missing, every call throws `KeychainError.platformUnsupported` with
the reason. SwiftyChain never falls back to plaintext. Headless servers usually have no
Secret Service; use a secret manager there instead.

Behavior that differs from Apple platforms:

| Option | On Linux |
|--------|----------|
| `isSynchronizable: true` | Throws `platformUnsupported` |
| `accessGroup` | Stored as an attribute; namespaces items but doesn't isolate them |
| `accessibility`, `comment` | Not stored |
| `cryptography` trait | Unavailable (it stores Apple `SecKey` values) |
| Unresponsive keyring or unanswered unlock prompt | Throws `KeychainError.timedOut` after 30 seconds |

> **Isolation**: Linux has no per-app keychain permissions. Once the keyring is unlocked,
> any program running as the same user can read its items, including SwiftyChain's.
> Apps distributed as Flatpak or Snap get per-app storage automatically: libsecret keeps
> their secrets in an app-private file encrypted with a key from the Secret portal.

## Traits

The Swift macros (`@KeychainItem`, `@KeychainScope`, `#keychainKey`) are included by default. Two optional traits gate specialised features:

| Trait | Feature | Enable when |
|-------|---------|-------------|
| `cryptography` | `kSecClassKey` support — store, load, and manage `SecKey` objects (Apple platforms only) | You need to sign/verify data or work with cryptographic keys |
| `observation` | `AsyncSequence`-based keychain change stream + `@Observable` integration | You need to react to keychain changes in real time |

Enable traits in your consuming `Package.swift`:

```swift
.product(name: "SwiftyChain", package: "SwiftyChain", traits: ["observation"])
```

Or when running tests locally:

```bash
xcrun swift test --traits "observation,cryptography"
```

## @KeychainStorage Limitations

`@KeychainStorage` is synchronous and safe for `@MainActor`-isolated types (comparable cost to a UserDefaults read). **Do not use it for items with accessibility settings that may trigger user-interaction prompts** — keychain calls run on the calling thread and can block it. Use the async `Keychain` actor for those items instead.

## Testing

SwiftyChain ships a separate `SwiftyChainTesting` product for downstream tests.

```swift
import SwiftyChain
import SwiftyChainTesting

let keychain: any KeychainProtocol = InMemoryKeychain()
let tokenKey = KeychainKey<String>(service: "com.example.app", account: "auth_token")

try await keychain.upsert("secret", for: tokenKey)
#expect(try await keychain.load(key: tokenKey) == "secret")
```

```swift
import SwiftyChain
import SwiftyChainTesting

let backend = InMemoryKeychainBackend()
let storage = KeychainStorage<String>(
    "auth_token",
    service: "com.example.app",
    backend: backend
)

storage.wrappedValue = "secret"
#expect(storage.wrappedValue == "secret")
```

## Development

```bash
xcrun swift build -Xswiftc -warnings-as-errors
xcrun swift test -Xswiftc -warnings-as-errors --enable-code-coverage
xcrun swift-format lint --recursive --strict Sources Tests Package.swift
```

Optional features are guarded by traits. Enable them explicitly when building or testing:

```bash
xcrun swift test --traits "observation,cryptography"
```

Set `SWIFTYCHAIN_RUN_KEYCHAIN_INTEGRATION=1` to opt into the suite that exercises the real Apple keychain.

On Linux, run the same suite against GNOME Keyring. The helper script starts a private
D-Bus session, unlocks a keyring, waits until it's ready, and stops the daemons afterwards
(needs `libsecret-1-0`, `gnome-keyring`, `dbus-x11`, and `procps`):

```bash
SWIFTYCHAIN_RUN_SECRET_SERVICE_INTEGRATION=1 scripts/with-gnome-keyring.sh swift test
```

To try Linux from a Mac, run the same commands in the `swift:6.3.3-noble` Docker image.
