# ``SwiftyChain/KeychainError``

## Overview

`KeychainError` covers every failure mode you might encounter when
interacting with the keychain. Pattern-match on specific cases to
provide targeted recovery.

```swift
do {
    try await Keychain.shared.save(token, for: key)
} catch KeychainError.duplicateItem {
    try await Keychain.shared.update(token, for: key)
} catch KeychainError.authenticationFailed {
    // Prompt for biometrics
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
