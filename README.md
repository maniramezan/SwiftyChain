# SwiftyChain

[![Docs](https://img.shields.io/badge/docs-GitHub_Pages-0969da?logo=github)](https://maniramezan.github.io/SwiftyChain/)

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

## Traits

Core keychain support is dependency-free beyond `Security.framework`. Optional traits are declared for macro, cryptography, and observation features as the implementation matures.

## Development

```bash
xcrun swift build -Xswiftc -warnings-as-errors
xcrun swift test -Xswiftc -warnings-as-errors --enable-code-coverage
xcrun swift-format lint --recursive --strict Sources Tests Package.swift
```

Optional features are guarded by traits. Enable them explicitly when building or testing:

```bash
xcrun swift test --traits "macros,observation,cryptography"
```

Set `SWIFTYCHAIN_RUN_KEYCHAIN_INTEGRATION=1` to opt into the suite that exercises the real Apple keychain.
