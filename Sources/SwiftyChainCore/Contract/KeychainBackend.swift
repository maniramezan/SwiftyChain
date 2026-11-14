import Foundation

/// Synchronous storage protocol used by ``KeychainStorage``.
///
/// This protocol stays intentionally small so downstream users can provide
/// simple in-memory fakes without depending on SwiftyChain's internal query types.
///
/// Implement `KeychainBackend` when you need a custom storage layer for
/// ``KeychainStorage``, or use `InMemoryKeychainBackend` from the
/// `SwiftyChainTesting` product in your test targets.
///
/// ```swift
/// // In tests
/// let backend = InMemoryKeychainBackend()
/// let storage = KeychainStorage<String>("token", service: "com.example", backend: backend)
/// ```
public protocol KeychainBackend: Sendable {
    /// Saves raw data for a new keychain item.
    ///
    /// - Throws: ``KeychainError/duplicateItem`` if an item with the same identity
    ///   (service + account + accessGroup + isSynchronizable) already exists.
    func save(
        _ data: Data,
        service: String,
        account: String,
        accessGroup: String?,
        accessibility: KeychainAccessibility,
        isSynchronizable: Bool,
        label: String?,
        comment: String?
    ) throws

    /// Loads the raw data for an existing keychain item.
    ///
    /// - Throws: ``KeychainError/itemNotFound`` if no matching item exists.
    func load(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool
    ) throws -> Data

    /// Replaces the raw data for an existing keychain item.
    ///
    /// - Throws: ``KeychainError/itemNotFound`` if no matching item exists.
    func update(
        _ data: Data,
        service: String,
        account: String,
        accessGroup: String?,
        accessibility: KeychainAccessibility,
        isSynchronizable: Bool,
        label: String?,
        comment: String?
    ) throws

    /// Removes a keychain item.
    ///
    /// This should be a no-op if the item does not exist.
    func delete(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool
    ) throws
}
