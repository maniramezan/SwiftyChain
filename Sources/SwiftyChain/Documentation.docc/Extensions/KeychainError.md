# ``SwiftyChain/KeychainError``

## Overview

`KeychainError` covers every failure mode you might encounter when
interacting with the keychain. Pattern-match on specific cases to
provide targeted recovery.

For most writes, use ``Keychain/upsert(_:for:)`` which handles
create-or-replace in one call and avoids the need to pattern-match on
``duplicateItem``:

```swift
// Preferred: upsert handles create-or-replace atomically
try await Keychain.shared.upsert(token, for: key)
```

When you do need to distinguish specific failures, pattern-match on the
error:

```swift
do {
    let token = try await Keychain.shared.load(key: key)
    use(token)
} catch KeychainError.itemNotFound {
    // First launch — nothing stored yet; redirect to login
} catch KeychainError.authenticationFailed {
    // Authentication failed — check key accessibility or prompt the user again
} catch KeychainError.accessGroupDenied {
    // Missing entitlements for the access group in the key
} catch {
    // Unexpected failure
    print("Keychain error:", error)
}
```

## Topics

### Cases

- ``itemNotFound``
- ``duplicateItem``
- ``authenticationFailed``
- ``userPresenceRequired``
- ``unexpectedData``
- ``encodingFailed(_:)``
- ``decodingFailed(_:)``
- ``operationFailed(_:)``
- ``accessGroupDenied``
- ``platformUnsupported(_:)``
