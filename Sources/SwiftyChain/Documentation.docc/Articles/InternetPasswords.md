# Internet Passwords

Store and retrieve `kSecClassInternetPassword` items with
``InternetPasswordKey``.

## Overview

While generic passwords (``KeychainKey``) are the most common keychain
item type, you sometimes need internet passwords -- items associated with
a server, port, protocol, and authentication type.

### Define a Key

```swift
let githubKey = InternetPasswordKey(
    server: "github.com",
    account: "octocat",
    protocol: .https,
    authenticationType: .httpBasic
)
```

### Save, Load, Delete

Use the dedicated methods on ``Keychain``:

```swift
// Save
try await Keychain.shared.saveInternetPassword("ghp_abc123", for: githubKey)

// Load
let password = try await Keychain.shared.loadInternetPassword(for: githubKey)

// Delete
try await Keychain.shared.deleteInternetPassword(for: githubKey)
```

### Item Identity

> Important: All fields of ``InternetPasswordKey`` — server, account, port,
> path, protocol, and authentication type — participate in item identity.
> Two keys with the same server and account but different ports or protocols
> refer to **different** keychain items. If you change any of these fields
> after storing a password, you will not find the existing item; you will
> create a new one instead.

### When to Use Internet Passwords

Use ``InternetPasswordKey`` when:

- You need to match items by server, port, or protocol (e.g., HTTP vs HTTPS).
- You want interoperability with Safari AutoFill or Passwords.app.
- The credential is server-specific rather than app-specific.

For app-internal secrets (tokens, preferences, encryption keys), prefer
``KeychainKey`` with generic passwords.
