# ``SwiftyChain/KeychainKey``

## Overview

A `KeychainKey` is a typed descriptor that identifies a single keychain
item. The generic `Value` parameter ensures you always encode and decode
the correct type.

```swift
// A key that stores a String under "api-token"
let key = KeychainKey<String>(
    service: "com.example.app",
    account: "api-token"
)

// A key that stores raw Data
let dataKey = KeychainKey<Data>(
    service: "com.example.app",
    account: "session-blob",
    accessibility: .afterFirstUnlock
)
```

Use the ``genericPassword(service:account:accessGroup:accessibility:isSynchronizable:)``
factory method for a shorter call site when label and comment are not needed.

## Topics

### Creating Keys

- ``init(service:account:accessGroup:accessibility:isSynchronizable:label:comment:)``
- ``genericPassword(service:account:accessGroup:accessibility:isSynchronizable:)``

### Properties

- ``service``
- ``account``
- ``accessGroup``
- ``accessibility``
- ``isSynchronizable``
- ``label``
- ``comment``
