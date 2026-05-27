# SwiftyChain

[![CI](https://img.shields.io/github/actions/workflow/status/maniramezan/SwiftyChain/ci.yml?branch=main&label=CI&logo=github)](https://github.com/maniramezan/SwiftyChain/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-GitHub_Pages-0969da?logo=github)](https://maniramezan.github.io/SwiftyChain/)
[![Swift](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2016%20%7C%20macOS%2013%20%7C%20tvOS%2016%20%7C%20watchOS%209%20%7C%20visionOS%201-blue)](https://github.com/maniramezan/SwiftyChain/blob/main/Package.swift)
[![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen?logo=swift&logoColor=white)](https://swift.org/package-manager)
[![License](https://img.shields.io/github/license/maniramezan/SwiftyChain)](LICENSE)

SwiftyChain is a Swift 6.3 keychain wrapper for Apple platforms. It provides a typed `Keychain` actor for async-safe access and an `@KeychainStorage` property wrapper for simple optional values.

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
| macOS     | 13.0+      |
| iOS       | 16.0+      |
| iPadOS    | 16.0+      |
| watchOS   | 9.0+       |
| tvOS      | 16.0+      |
| visionOS  | 1.0+       |

> **tvOS note**: `whenPasscodeSetThisDeviceOnly` accessibility is unavailable on tvOS. The `#keychainKey` macro emits a warning if you use it on that platform.

## Traits

The Swift macros (`@KeychainItem`, `@KeychainScope`, `#keychainKey`) are included by default. Two optional traits gate specialised features:

| Trait | Feature | Enable when |
|-------|---------|-------------|
| `cryptography` | `kSecClassKey` support — store, load, and manage `SecKey` objects | You need to sign/verify data or work with cryptographic keys |
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

`@KeychainStorage` is synchronous and safe for `@MainActor`-isolated types (comparable cost to a UserDefaults read). **Do not use it for items with accessibility settings that may trigger user-interaction prompts** — those can block the calling thread. Use the async `Keychain` actor for those items instead.

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
