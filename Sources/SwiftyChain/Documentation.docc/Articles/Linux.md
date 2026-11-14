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

The binary must also be dynamically linked: one built with the Static Linux SDK (musl)
can't load libsecret, and every call throws ``KeychainError/platformUnsupported(_:)``
saying so.

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
| Strings containing a NUL character | Throws ``KeychainError/platformUnsupported(_:)``. libsecret reads attributes as C strings, so it would otherwise see only the text before the NUL. |
| ``Keychain/deleteAllItems(matching:)`` without a service, server, or access group, or without an exact item | Throws ``KeychainError/platformUnsupported(_:)``; see <doc:#Isolation-between-applications>. |
| `cryptography` trait | Unavailable; it stores Apple `SecKey` values. |

Values are stored as binary data with no size limit, so every ``KeychainStorable`` type
round-trips exactly.

Within one process, SwiftyChain serializes every Secret Service call, across all
``Keychain`` instances and ``KeychainStorage`` wrappers. Concurrent saves of the same item
therefore behave as on Apple platforms: one succeeds and the others throw
``KeychainError/duplicateItem``. Separate processes still race. On Apple, the second
process's `save` throws ``KeychainError/duplicateItem``; on Linux, each write replaces
the item in the keyring, so the last one wins. ``Keychain/upsert(_:for:)`` avoids the
difference everywhere.

### Unlock prompts and timeouts

If the keyring is locked, the Secret Service asks the user to unlock it, and the call waits
for the answer. Only calls that need a secret or change the keyring ask: loading, saving,
updating, and deleting. ``Keychain/exists(key:)`` and ``Keychain/allAccounts(service:accessGroup:)``
read item attributes, which stay readable while the keyring is locked, so they never prompt.

Each request to the keyring gives up after 30 seconds and throws ``KeychainError/timedOut``,
so an unanswered prompt or an unresponsive keyring daemon can't block your app forever.
The 30 seconds include time spent waiting for another SwiftyChain call in the same process
to finish, so calls queued behind an unanswered prompt all time out together rather than
one after another. A slow or hung D-Bus session bus also throws ``KeychainError/timedOut``,
not ``KeychainError/platformUnsupported(_:)``, because it may recover. Most operations
make one request. ``Keychain/upsert(_:for:)`` makes two when the item already exists (a
save that finds the duplicate, then an update), so it can wait up to 60 seconds.

If the keyring daemon or the session bus restarts while your app runs, SwiftyChain
reconnects on the next call, so a long-running process doesn't need restarting.

When an unlock attempt leaves an existing item locked, reads and deletions throw
``KeychainError/userPresenceRequired``. libsecret reports a dismissed prompt and a prompt
that couldn't be shown the same way, so both surface as this error. A dismissed prompt
never makes an existing credential appear missing, and deletion succeeds only when no
matching items remain.

The ``Keychain`` actor runs on its own dispatch queue on Linux, so a call waiting on the
keyring never blocks Swift's shared concurrency thread pool. ``KeychainStorage`` is
synchronous and blocks the calling thread while it waits, so prefer the ``Keychain`` actor
on the main thread.

Providers that have no default collection, such as KeePassXC before a database exposes
one, can't store new items. Saves then throw ``KeychainError/platformUnsupported(_:)``
saying so. New items always go to the default collection; updates change an item in
whichever collection holds it.

An update that matches several items changes them one at a time. The Secret Service has
no transactions, so if one write fails, SwiftyChain tries to put back the items it already
changed before throwing. It can't when the failure is a timeout, because the keyring isn't
responding.

### Isolation between applications

The Secret Service has no per-application permissions. Once the user's keyring is unlocked,
usually at login, any program running as that user can read every item in it, including
SwiftyChain's. ``KeychainKey/accessGroup`` organizes items; it doesn't protect them.

Sandboxed apps can be the exception. When libsecret 0.20 or newer, built with its optional
crypto support, runs inside Flatpak or Snap and the host provides the
[Secret portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Secret.html),
libsecret stores secrets in a file inside the app's own data directory, encrypted with a
per-app key from the portal, so other apps can't read them. GNOME provides the portal.
Otherwise, sandboxed apps use the host's Secret Service like any other program.

SwiftyChain stores items under its own schemas (`dev.manman.SwiftyChain.GenericPassword` and
`dev.manman.SwiftyChain.InternetPassword`), so its queries never touch items that other
programs store. Every app built on SwiftyChain shares those schemas, though, and the Secret
Service has no app sandbox to tell their items apart. Use a service name unique to your app,
such as its reverse-DNS identifier. For the same reason, a delete must name a non-empty service
(or server, for internet passwords) or access group, or one exact item: a service or
server, even an empty one, together with an account. Otherwise
``Keychain/deleteAllItems(matching:)`` throws ``KeychainError/platformUnsupported(_:)``
instead of removing every SwiftyChain app's items. Deleting an item that is already gone,
even one another process removed mid-call, succeeds.

### Logging

On Linux, SwiftyChain logs through [swift-log](https://github.com/apple/swift-log) with
labels starting with `dev.manman.SwiftyChain`. Service, account, and server names are never
logged in clear text.

Failures you receive as errors — including ``KeychainError/platformUnsupported(_:)`` for a
missing libsecret, D-Bus session, or Secret Service provider — are logged at debug level,
because the thrown error is the primary signal your code acts on. Only platform faults
(`KeychainError/unexpectedData` and `KeychainError/operationFailed(_:)`) are logged as
errors. If debugging a missing keyring setup, turn debug logging on for the
`dev.manman.SwiftyChain` labels.
