import Foundation

/// The storage contract behind ``Keychain``, `KeychainStorage`, and the in-memory test doubles.
///
/// SwiftyChain ships a backend for each platform it supports, and `SwiftyChainTesting`
/// ships `InMemoryKeychainBackend`. Implement this protocol to store items somewhere else,
/// then pass the backend to `Keychain(backend:)` or `KeychainStorage(_:service:backend:)`.
///
/// ```swift
/// let keychain = Keychain(backend: InMemoryKeychainBackend())
/// ```
///
/// Callers never pass a backend an option it doesn't support: `Keychain` validates every
/// query against ``capabilities`` first. Backends must follow these rules:
///
/// - A `nil` attribute in a ``KeychainQuery`` matches any value, and
///   `isSynchronizable == nil` matches both synchronizable and local items.
/// - ``add(_:attributes:)`` throws ``KeychainError/duplicateItem`` when an item with the
///   same identity already exists.
/// - ``data(matching:)`` throws ``KeychainError/itemNotFound`` when nothing matches.
/// - ``contains(matching:)`` and ``accounts(matching:)`` report an empty result instead
///   of throwing ``KeychainError/itemNotFound``.
/// - ``update(matching:to:)`` changes every matching item and throws
///   ``KeychainError/itemNotFound`` when nothing matches.
/// - ``delete(matching:)`` removes every matching item and succeeds when nothing matches.
/// - Errors are ``KeychainError`` values. Platform diagnostics are logged, never carried
///   in the error.
public protocol KeychainBackend: Sendable {
    /// The optional features this backend supports.
    var capabilities: KeychainBackendCapabilities { get }

    /// Stores a new item described by `query`, with `attributes.data` as its secret.
    func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws

    /// Returns the secret of the first matching item.
    func data(matching query: KeychainQuery) throws -> Data

    /// Returns whether any item matches, without reading its secret.
    func contains(matching query: KeychainQuery) throws -> Bool

    /// Returns the account of every matching item.
    func accounts(matching query: KeychainQuery) throws -> [String]

    /// Writes the non-`nil` values in `attributes` to every matching item.
    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws

    /// Removes every matching item.
    func delete(matching query: KeychainQuery) throws
}

/// Optional features a ``KeychainBackend`` supports beyond generic passwords.
///
/// ``KeychainAccessibility`` is deliberately not a capability: it only narrows when an
/// item is readable, so a backend that can't honor it, such as Linux's Secret Service,
/// ignores it instead of failing.
public struct KeychainBackendCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Items can sync across devices (`isSynchronizable: true`).
    public static let synchronizable = KeychainBackendCapabilities(rawValue: 1 << 0)
    /// Items can be scoped to an access group.
    public static let accessGroups = KeychainBackendCapabilities(rawValue: 1 << 1)
    /// The backend stores internet passwords.
    public static let internetPasswords = KeychainBackendCapabilities(rawValue: 1 << 2)
    /// The backend stores cryptographic keys, through `KeychainCryptoBackend`.
    public static let cryptoKeys = KeychainBackendCapabilities(rawValue: 1 << 3)
    /// Bulk deletes may omit the service, server, and access group.
    ///
    /// Apple's keychain scopes every query to the calling app, so an unscoped delete only
    /// removes that app's items. The Secret Service has no such sandbox: every app built
    /// on SwiftyChain shares its schemas, so an unscoped delete there would remove other
    /// apps' items.
    public static let unscopedBulkDelete = KeychainBackendCapabilities(rawValue: 1 << 4)
    /// Items can require user presence, biometry, or the device passcode before they are read.
    public static let accessControl = KeychainBackendCapabilities(rawValue: 1 << 5)

    /// Every capability.
    public static let all: KeychainBackendCapabilities = [
        .synchronizable,
        .accessGroups,
        .internetPasswords,
        .cryptoKeys,
        .unscopedBulkDelete,
        .accessControl,
    ]
}
