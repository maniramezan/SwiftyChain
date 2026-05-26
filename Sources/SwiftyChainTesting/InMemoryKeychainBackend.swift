import Foundation
import SwiftyChain

/// An in-memory implementation of `KeychainBackend` for use in tests.
///
/// Use `InMemoryKeychainBackend` when initialising `KeychainStorage` directly in
/// unit tests. Items are stored in a dictionary and never touch the system keychain,
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
/// `InMemoryKeychainBackend` is `Sendable` and uses `NSLock` to serialize
/// concurrent reads and writes, so it is safe to share across threads or tasks.
public final class InMemoryKeychainBackend: KeychainBackend, @unchecked Sendable {
    private struct StorageKey: Hashable {
        let service: String
        let account: String
        let accessGroup: String?
        let isSynchronizable: Bool
    }

    private struct StorageValue {
        let data: Data
        let accessibility: KeychainAccessibility
        let label: String?
        let comment: String?
    }

    private let lock = NSLock()
    private var items: [StorageKey: StorageValue] = [:]

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
        let key = StorageKey(
            service: service,
            account: account,
            accessGroup: accessGroup,
            isSynchronizable: isSynchronizable
        )
        try withLock {
            if items[key] != nil {
                throw KeychainError.duplicateItem
            }
            items[key] = StorageValue(
                data: data,
                accessibility: accessibility,
                label: label,
                comment: comment
            )
        }
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
        let key = StorageKey(
            service: service,
            account: account,
            accessGroup: accessGroup,
            isSynchronizable: isSynchronizable
        )
        return try withLock {
            guard let item = items[key] else {
                throw KeychainError.itemNotFound
            }
            return item.data
        }
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
        let key = StorageKey(
            service: service,
            account: account,
            accessGroup: accessGroup,
            isSynchronizable: isSynchronizable
        )
        try withLock {
            guard items[key] != nil else {
                throw KeychainError.itemNotFound
            }
            items[key] = StorageValue(
                data: data,
                accessibility: accessibility,
                label: label,
                comment: comment
            )
        }
    }

    /// Removes a keychain item. This is a no-op if the item does not exist.
    public func delete(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool
    ) throws {
        let key = StorageKey(
            service: service,
            account: account,
            accessGroup: accessGroup,
            isSynchronizable: isSynchronizable
        )
        _ = withLock {
            items.removeValue(forKey: key)
        }
    }

    private func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
