# Migrating to 2.0

Update custom backends, key policies, error handling, and observation for SwiftyChain 2.0.0.

## Overview

Version 2.0.0 has breaking API changes. No item migration happens automatically.

### Custom backends

Replace the four-method backend with ``KeychainBackend``: `capabilities`, `add`, `data`,
`contains`, `accounts`, `update`, and `delete`. ``KeychainQuery`` is public and contains
matching attributes only. Write values move to ``KeychainAttributes``. Return raw data,
booleans, or account arrays instead of recursive query results. `SecureStorageBackend`,
`SecureStorageCapabilities`, `KeychainQueryResult`, `KeychainAttribute`, and match/return flags
are removed. The optional crypto refinement is `KeychainCryptoBackend`.

Pass a backend to `Keychain(backend:)`. `KeychainStorage` now uses the same engine, including
capability checks and observation. `InMemoryKeychainBackend` replaces the separate in-memory
storage implementation. Use `InMemoryKeychain(emulating: .linux)` to exercise Linux restrictions;
NUL rejection is a libsecret backend restriction and is not emulated.

### Keys and policies

Accessibility is optional and defaults to `nil`: new items use the platform default, while
updates preserve existing accessibility. Macros and `KeychainStorage` follow this rule.
Explicitly pass `.whenUnlocked` if an update should reset an existing policy.

Generic keys compare and hash service, account, access group, and synchronization only.
Internet keys use their internet identity and synchronization; crypto references use tag
and access group. Accessibility, access control, labels, and comments are write policy.

Synchronizable items reject `ThisDeviceOnly` accessibility and access control with
``KeychainError/invalidArgument(_:)``. Internet-password deletion now honors synchronization
filters. Cryptographic bulk deletion has no service: scope it by access group instead.

`saveCryptoKey` throws on duplicates. `upsertCryptoKey` updates in place without deleting
first. Replacement material must be exportable. macOS legacy-store material updates throw
`invalidArgument`; use the data-protection store. Signed-host verification of that update
path remains necessary.

### Errors

Rename `interactionNotAllowed` to ``KeychainError/interactionNotAllowed``. It usually means
locked storage or unavailable interaction, rather than a biometric requirement.
``KeychainError/userCanceled`` distinguishes explicit cancellation from failed authentication.
On Linux, cancellation from SwiftyChain's own timer stays ``KeychainError/timedOut``; an
existing item left locked can still produce `interactionNotAllowed` when libsecret does not
distinguish why unlocking failed.

``KeychainError/operationFailed(_:)`` still carries a platform-specific `Int32`: Security's
`OSStatus` on Apple, libsecret or GLib codes on Linux. Consult logs for the Linux error domain.

### macOS store and user authentication

The default remains the legacy login keychain. Opt in explicitly:

```swift
let keychain = Keychain(configuration: .init(macOSStore: .dataProtection))
let key = KeychainKey<String>(
    service: "com.example.app",
    account: "protected-token",
    accessibility: .whenUnlockedThisDeviceOnly,
    accessControl: .userPresence
)
try await keychain.upsert("secret", for: key)
```

The data-protection store requires a signed, entitled host. It is separate from the legacy
store; switching configuration does not move credentials. Linux, tvOS, and the macOS legacy
store reject access control. In-memory storage records the policy without prompting.
Authentication uses the system prompt; 2.0 has no `LAContext` parameter.

### Observation and execution

Platform-backed `Keychain` instances and `KeychainStorage` share observers, including those
registered with `Keychain.shared`. Custom backends have a registry per engine. Internet events
use `server` and have a `nil` service; generic events use `service` and have a `nil` server.
Use `observeKeychainChanges(server:)` for internet passwords.

Apple and Linux actors run blocking calls on a dedicated dispatch queue. `KeychainStorage`
remains synchronous and can block its calling thread. Prefer the actor for protected items.
