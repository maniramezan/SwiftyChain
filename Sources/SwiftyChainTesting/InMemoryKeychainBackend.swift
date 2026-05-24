import Foundation
import SwiftyChain

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

    public init() {}

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
