import Foundation
import SwiftyChain

/// An in-memory implementation of `KeychainBackend` for use in tests.
///
/// Use `InMemoryKeychainBackend` when initialising `KeychainStorage` directly in
/// unit tests. Items are stored in memory and never touch the system keychain,
/// so tests run fast and require no entitlements.
///
/// ```swift
/// import SwiftyChain
/// import SwiftyChainTesting
///
/// let backend = InMemoryKeychainBackend()
/// let storage = KeychainStorage<String>(
///     "auth-token",
///     service: "com.example.app",
///     backend: backend
/// )
///
/// storage.wrappedValue = "secret"
/// assert(storage.wrappedValue == "secret")
/// ```
///
/// Each instance starts empty. Create a fresh one per test to guarantee isolation.
///
/// ## Thread safety
///
/// `InMemoryKeychainBackend` is `Sendable` and serializes concurrent reads and
/// writes, so it is safe to share across threads or tasks.
public final class InMemoryKeychainBackend: KeychainBackend, Sendable {
    private let adapter = SecureStorageKeychainBackend(InMemoryStorageBackend())

    /// Creates a new, empty in-memory keychain backend.
    public init() {}

    /// Saves raw data for a new keychain item.
    ///
    /// - Throws: `KeychainError.duplicateItem` if an item with the same identity already exists.
    public func save(
        _ data: Data,
        service: String,
        account: String,
        accessGroup: String?,
        accessibility: KeychainAccessibility,
        isSynchronizable: Bool,
        label: String?,
        comment: String?
    ) throws {
        try adapter.save(
            data,
            service: service,
            account: account,
            accessGroup: accessGroup,
            accessibility: accessibility,
            isSynchronizable: isSynchronizable,
            label: label,
            comment: comment
        )
    }

    /// Loads the raw data for an existing keychain item.
    ///
    /// - Throws: `KeychainError.itemNotFound` if no matching item exists.
    public func load(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool
    ) throws -> Data {
        try adapter.load(
            service: service, account: account, accessGroup: accessGroup, isSynchronizable: isSynchronizable)
    }

    /// Replaces the raw data for an existing keychain item.
    ///
    /// - Throws: `KeychainError.itemNotFound` if no matching item exists.
    public func update(
        _ data: Data,
        service: String,
        account: String,
        accessGroup: String?,
        accessibility: KeychainAccessibility,
        isSynchronizable: Bool,
        label: String?,
        comment: String?
    ) throws {
        try adapter.update(
            data,
            service: service,
            account: account,
            accessGroup: accessGroup,
            accessibility: accessibility,
            isSynchronizable: isSynchronizable,
            label: label,
            comment: comment
        )
    }

    /// Removes a keychain item. This is a no-op if the item does not exist.
    public func delete(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool
    ) throws {
        try adapter.delete(
            service: service, account: account, accessGroup: accessGroup, isSynchronizable: isSynchronizable)
    }
}
