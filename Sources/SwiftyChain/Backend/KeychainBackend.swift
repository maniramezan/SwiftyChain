import Foundation

/// Synchronous storage protocol used by ``KeychainStorage``.
///
/// This protocol stays intentionally small so downstream users can provide
/// simple in-memory fakes without depending on SwiftyChain's internal query types.
public protocol KeychainBackend: Sendable {
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

    func load(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool
    ) throws -> Data

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

    func delete(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool
    ) throws
}
