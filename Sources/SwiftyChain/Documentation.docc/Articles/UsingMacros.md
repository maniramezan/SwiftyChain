# Using Macros

Reduce boilerplate with SwiftyChain's Swift macros.

## Overview

SwiftyChain ships three macros that generate keychain plumbing at compile
time, available out of the box with no extra trait required.

### @KeychainScope

Annotate a type to group related keychain items under a shared service
and gain a `static deleteAll()` helper that bulk-deletes every item
stored under that service:

```swift
@KeychainScope(service: "com.example.app")
final class Secrets {
    @KeychainItem("api-token")
    var apiToken: String?

    @KeychainItem("refresh-token")
    var refreshToken: String?
}

let secrets = Secrets()
try await secrets.setApiToken("abc123")   // saves to keychain
let token = try await secrets.apiToken    // loads; nil if absent
try await secrets.setApiToken(nil)        // deletes

try await Secrets.deleteAll()             // bulk-deletes all items for the service
```

The scope macro adds a `static func deleteAll()` to the annotated type.
`@KeychainItem` properties inside a scope omit `service:` —
the scope injects it automatically into every generated ``KeychainKey``.

### @KeychainItem

Attach to a stored property to generate a backing ``KeychainKey``, an
`async throws` computed getter, and a `setXyz(_:)` async peer method:

```swift
@KeychainItem(
    "device-secret",
    service: "com.example.app",
    accessibility: .whenPasscodeSetThisDeviceOnly
)
var deviceSecret: Data?
```

`service:` and the account (first argument) must be non-empty string
literals; the macro emits a compile-time diagnostic if either is empty.
Passing `nil` to the generated setter deletes the item; non-optional
properties always upsert.

### #keychainKey

A freestanding expression macro that creates a ``KeychainKey`` inline and
validates its string-literal arguments at compile time (for example,
flagging `isSynchronizable: true` combined with a `ThisDeviceOnly`
accessibility):

```swift
let key: KeychainKey<String> = #keychainKey(
    service: "com.example.app",
    account: "token"
)
```

## Testing Macro-Generated Code

Pass a `keychain:` argument to `@KeychainScope` to control which
``KeychainProtocol`` implementation the generated accessors use. When omitted,
it defaults to `Keychain.shared`.

```swift
@KeychainScope(service: "com.example.app", keychain: AppDependencies.keychain)
final class Secrets {
    @KeychainItem("api-token")
    var apiToken: String?
}
```

Define `AppDependencies.keychain` to switch between the real keychain and
an `InMemoryKeychain` based on a launch-time signal:

```swift
// AppDependencies.swift — compiled into the app target
import SwiftyChain
import SwiftyChainTesting   // only in DEBUG builds

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
```

In UI tests, set the environment variable before launch:

```swift
func testLoginFlow() {
    let app = XCUIApplication()
    app.launchEnvironment["USE_MOCK_KEYCHAIN"] = "1"
    app.launch()
    // Secrets now reads and writes to InMemoryKeychain
}
```

The `#if DEBUG` guard ensures no `SwiftyChainTesting` code ships in
Release builds.

> Note: `@KeychainItem` used without an enclosing `@KeychainScope` always
> falls back to `Keychain.shared`. Add a `@KeychainScope` wrapper to opt in
> to the injection point. For fine-grained unit-test control, write feature
> code against ``KeychainProtocol`` directly — see <doc:Testing>.

See <doc:Testing> for guidance on when to use the real keychain versus
in-memory test doubles.
