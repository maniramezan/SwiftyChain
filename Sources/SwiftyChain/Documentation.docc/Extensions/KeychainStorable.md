# ``SwiftyChain/KeychainStorable``

## Overview

Conform your types to `KeychainStorable` to persist them in the keychain.
SwiftyChain ships with built-in conformances for `String`, `Data`, `Bool`,
`Int`, `Double`, and `UInt64`.

For arbitrary `Codable` types, wrap them with ``CodableKeychainStorable``.

See <doc:CustomStorableTypes> for a step-by-step guide on adding your own
conformance.

## Built-in Conformances

SwiftyChain provides `KeychainStorable` conformance for:

- `String` (UTF-8)
- `Data` (passthrough)
- `Bool` (single byte)
- `Int` (little-endian)
- `Double` (bit pattern)
- `UInt64` (little-endian)

## Topics

### Requirements

- ``keychainData()``
- ``fromKeychainData(_:)``
