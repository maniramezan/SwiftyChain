# Custom Storable Types

Conform your own types to ``KeychainStorable`` to persist them in the keychain.

## Overview

SwiftyChain ships with conformances for `String`, `Data`, `Bool`, `Int`,
`Double`, and `UInt64`. For anything else you have two options:

1. **Use ``CodableKeychainStorable``** for `Codable` types (zero effort).
2. **Conform directly** for full control over serialization.

### Option 1: CodableKeychainStorable

Wrap any `Codable & Sendable` value in ``CodableKeychainStorable`` and use
a `KeychainKey<CodableKeychainStorable<YourType>>`:

```swift
struct Credentials: Codable, Sendable {
    let username: String
    let password: String
}

let key = KeychainKey<CodableKeychainStorable<Credentials>>(
    service: "com.example.app",
    account: "credentials"
)

let creds = CodableKeychainStorable(
    Credentials(username: "alice", password: "s3cret")
)
try await Keychain.shared.save(creds, for: key)
```

This uses a binary property list under the hood, which is compact and
fast.

### Option 2: Direct Conformance

Implement ``KeychainStorable/keychainData()`` and
``KeychainStorable/fromKeychainData(_:)`` yourself. Wrap any serialization
errors in ``KeychainError/encodingFailed(_:)`` or
``KeychainError/decodingFailed(_:)`` so callers get consistent error types:

```swift
struct APIToken: KeychainStorable {
    let raw: String
    let expiresAt: Date

    func keychainData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(Wrapper(raw: raw, expiresAt: expiresAt))
        } catch {
            throw KeychainError.encodingFailed(error)
        }
    }

    static func fromKeychainData(_ data: Data) throws -> APIToken {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let wrapper = try decoder.decode(Wrapper.self, from: data)
            return APIToken(raw: wrapper.raw, expiresAt: wrapper.expiresAt)
        } catch {
            throw KeychainError.decodingFailed(error)
        }
    }

    private struct Wrapper: Codable {
        let raw: String
        let expiresAt: Date
    }
}
```

> Important: Always wrap your encoder/decoder errors in
> ``KeychainError/encodingFailed(_:)`` or ``KeychainError/decodingFailed(_:)``
> rather than letting them propagate as raw `EncodingError` or `DecodingError`.
> This ensures callers can pattern-match on ``KeychainError`` uniformly,
> regardless of which serialization strategy you choose.
