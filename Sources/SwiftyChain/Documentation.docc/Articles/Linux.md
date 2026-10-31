# Using SwiftyChain on Linux

Store secrets in the freedesktop Secret Service with the same code you use on Apple platforms.

## Overview

On Linux, ``Keychain/shared``, `Keychain()`, and ``KeychainStorage`` store secrets in the
[Secret Service](https://specifications.freedesktop.org/secret-service-spec/latest/), the
standard desktop keyring API implemented by GNOME Keyring, KWallet, KeePassXC, and others.
Your code doesn't change:

```swift
import SwiftyChain

let tokenKey = KeychainKey<String>(service: "com.example.app", account: "auth-token")
try await Keychain.shared.upsert("secret", for: tokenKey)
let token = try await Keychain.shared.loadIfPresent(key: tokenKey)
```

### Requirements

SwiftyChain loads [libsecret](https://gnome.pages.gitlab.gnome.org/libsecret/) at runtime,
so building needs no extra packages. To store secrets, the machine running your app needs:

- libsecret 0.19 or newer: `libsecret-1-0` on Debian and Ubuntu, `libsecret` on Fedora.
- A D-Bus session bus.
- A running Secret Service provider, such as GNOME Keyring or KWallet.

Desktop sessions normally provide all three. Headless servers, containers, and SSH sessions
usually don't; use your platform's secret manager there instead.

When something is missing, every call throws ``KeychainError/platformUnsupported(_:)``
with a message naming the missing piece. SwiftyChain never falls back to storing secrets
in plaintext or in memory.

### Differences from Apple platforms

| Option | On Linux |
|---|---|
| ``KeychainKey/isSynchronizable`` set to `true` | Throws ``KeychainError/platformUnsupported(_:)``; there is no cross-device sync. |
| ``KeychainKey/accessGroup`` | Stored as an item attribute. Lookups and bulk deletes are scoped to it, but see <doc:#Isolation-between-applications>. |
| ``KeychainKey/accessibility`` | Not stored. The keyring's own lock state controls access. |
| ``KeychainKey/comment`` | Not stored. |
| ``KeychainKey/label`` | Shown as the item name in keyring managers such as Seahorse. Defaults to `service (account)`. |
| `cryptography` trait | Unavailable; it stores Apple `SecKey` values. |

Values are stored as binary data with no size limit, so every ``KeychainStorable`` type
round-trips exactly.

### Unlock prompts and timeouts

If the keyring is locked, the Secret Service asks the user to unlock it, and the call waits
for the answer. Each call gives up after 30 seconds and throws ``KeychainError/timedOut``,
so an unanswered prompt or an unresponsive keyring daemon can't block your app forever.
When the keyring is locked and no prompt can be shown, the call throws
``KeychainError/userPresenceRequired``.

Like ``KeychainStorage`` on Apple platforms, calls block the calling thread while they wait.
Prefer the ``Keychain`` actor over ``KeychainStorage`` on the main thread.

### Isolation between applications

The Secret Service has no per-application permissions. Once the user's keyring is unlocked,
usually at login, any program running as that user can read every item in it, including
SwiftyChain's. ``KeychainKey/accessGroup`` organizes items; it doesn't protect them.

Sandboxed apps are the exception. Inside Flatpak or Snap, libsecret stores secrets in a file
inside the app's own data directory, encrypted with a per-app key obtained from the
[Secret portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Secret.html),
so other sandboxed apps can't read them. This needs a Secret portal implementation on the
host, which GNOME provides.

SwiftyChain stores items under its own schemas (`dev.manman.SwiftyChain.GenericPassword` and
`dev.manman.SwiftyChain.InternetPassword`), so bulk deletes such as
``Keychain/deleteAll(service:accessGroup:)`` never remove other applications' items.

### Logging

On Linux, SwiftyChain logs through [swift-log](https://github.com/apple/swift-log) with
labels starting with `dev.manman.SwiftyChain`. Service, account, and server names are never
logged in clear text.
