import Foundation

/// Adapts any ``SecureStorageBackend`` to the public ``KeychainBackend`` protocol
/// that ``KeychainStorage`` uses, validating every query against the backend's
/// capabilities first.
package struct SecureStorageKeychainBackend: KeychainBackend {
    private let backend: any SecureStorageBackend

    package init(_ backend: any SecureStorageBackend) {
        self.backend = backend
    }

    package func save(
        _ data: Data,
        service: String,
        account: String,
        accessGroup: String?,
        accessibility: KeychainAccessibility,
        isSynchronizable: Bool,
        label: String?,
        comment: String?
    ) throws {
        let query = KeychainQuery(
            itemClass: .genericPassword,
            service: service,
            account: account,
            accessGroup: accessGroup,
            accessibility: accessibility,
            isSynchronizable: isSynchronizable,
            label: label,
            comment: comment
        )
        try SecureStorageQueryValidator.validate(query, against: backend.capabilities)
        try backend.add(query, data: data)
    }

    package func load(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool
    ) throws -> Data {
        let query = identityQuery(
            service: service,
            account: account,
            accessGroup: accessGroup,
            isSynchronizable: isSynchronizable,
            returnData: true
        )
        try SecureStorageQueryValidator.validate(query, against: backend.capabilities)
        guard case .data(let data) = try backend.copyMatching(query) else {
            SwiftyChainLoggers.backend.error("copyMatching returned a non-data result for a data query")
            throw KeychainError.unexpectedData
        }
        return data
    }

    package func update(
        _ data: Data,
        service: String,
        account: String,
        accessGroup: String?,
        accessibility: KeychainAccessibility,
        isSynchronizable: Bool,
        label: String?,
        comment: String?
    ) throws {
        let query = identityQuery(
            service: service,
            account: account,
            accessGroup: accessGroup,
            isSynchronizable: isSynchronizable
        )
        try SecureStorageQueryValidator.validate(query, against: backend.capabilities)
        try backend.update(
            matching: query,
            to: KeychainAttributes(data: data, label: label, comment: comment, accessibility: accessibility)
        )
    }

    package func delete(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool
    ) throws {
        let query = identityQuery(
            service: service,
            account: account,
            accessGroup: accessGroup,
            isSynchronizable: isSynchronizable
        )
        try SecureStorageQueryValidator.validate(query, against: backend.capabilities)
        try backend.delete(matching: query)
    }

    private func identityQuery(
        service: String,
        account: String,
        accessGroup: String?,
        isSynchronizable: Bool,
        returnData: Bool = false
    ) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: service,
            account: account,
            accessGroup: accessGroup,
            isSynchronizable: isSynchronizable,
            returnData: returnData
        )
    }
}
