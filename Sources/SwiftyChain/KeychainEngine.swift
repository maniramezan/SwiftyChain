import Foundation

/// The platform-neutral implementation behind ``Keychain`` and `InMemoryKeychain`.
///
/// The engine turns public operations into ``KeychainQuery`` values, validates them
/// against the backend's capabilities, calls the ``SecureStorageBackend``, and emits
/// observation events. Every backend shares this logic, so they behave the same.
package struct KeychainEngine: Sendable {
    package let backend: any SecureStorageBackend
    #if Observation
        private let observers = KeychainObserverRegistry()
    #endif

    package init(backend: any SecureStorageBackend) {
        self.backend = backend
    }

    package func save<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        logKeychainOperationStarted("save", service: key.service, account: key.account)
        do {
            try add(value, for: key)
            logKeychainOperationSucceeded("save", service: key.service, account: key.account)
        } catch {
            logKeychainOperationFailed("save", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    package func load<T: KeychainStorable>(key: KeychainKey<T>) throws -> T {
        logKeychainOperationStarted("load", service: key.service, account: key.account)
        do {
            let result = try backend.copyMatching(validated(identityQuery(for: key, returnData: true)))
            guard case .data(let data) = result else {
                SwiftyChainLoggers.keychain.error(
                    "load returned unexpected result for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
                )
                throw KeychainError.unexpectedData
            }
            return try T.fromKeychainData(data)
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "load returned item not found for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            throw KeychainError.itemNotFound
        } catch {
            logKeychainOperationFailed("load", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    package func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T? {
        do {
            return try load(key: key)
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "loadIfPresent returned nil for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            return nil
        }
    }

    package func update<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        logKeychainOperationStarted("update", service: key.service, account: key.account)
        do {
            try backend.update(
                matching: validated(identityQuery(for: key)),
                to: KeychainAttributes(
                    data: try value.keychainData(),
                    label: key.label,
                    comment: key.comment,
                    accessibility: key.accessibility
                )
            )
            notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .updated)
            logKeychainOperationSucceeded("update", service: key.service, account: key.account)
        } catch {
            logKeychainOperationFailed("update", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    package func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        logKeychainOperationStarted("upsert", service: key.service, account: key.account)
        do {
            try add(value, for: key)
            logKeychainOperationSucceeded("upsert", service: key.service, account: key.account)
        } catch KeychainError.duplicateItem {
            SwiftyChainLoggers.keychain.debug(
                "upsert found duplicate item; updating instead for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            try update(value, for: key)
            logKeychainOperationSucceeded("upsert", service: key.service, account: key.account)
        } catch {
            logKeychainOperationFailed("upsert", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    package func delete<T: KeychainStorable>(key: KeychainKey<T>) throws {
        logKeychainOperationStarted("delete", service: key.service, account: key.account)
        do {
            try backend.delete(matching: validated(identityQuery(for: key)))
            notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .deleted)
            logKeychainOperationSucceeded("delete", service: key.service, account: key.account)
        } catch {
            logKeychainOperationFailed("delete", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    package func deleteAllItems(matching query: KeychainDeleteQuery) throws {
        let isSynchronizable: Bool? =
            if query.onlySynchronizable {
                true
            } else if query.includeSynchronizable {
                nil
            } else {
                false
            }
        logBulkDeleteStarted(query: query)
        do {
            // Internet passwords use kSecAttrServer, not kSecAttrService.
            let keychainQuery =
                query.itemClass == .internetPassword
                ? KeychainQuery(
                    itemClass: query.itemClass,
                    accessGroup: query.accessGroup,
                    server: query.service
                )
                : KeychainQuery(
                    itemClass: query.itemClass,
                    service: query.service,
                    accessGroup: query.accessGroup,
                    isSynchronizable: isSynchronizable
                )
            try backend.delete(matching: validated(keychainQuery))
            if let service = query.service {
                notify(service: service, account: nil, accessGroup: query.accessGroup, kind: .bulkDeleted)
            }
            logBulkDeleteSucceeded(query: query)
        } catch {
            logBulkDeleteFailed(query: query, error: error)
            throw error
        }
    }

    package func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool {
        do {
            _ = try backend.copyMatching(validated(identityQuery(for: key)))
            return true
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "exists returned false for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            return false
        } catch {
            logKeychainOperationFailed("exists", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    package func allAccounts(service: String, accessGroup: String?) throws -> [String] {
        let result: KeychainQueryResult
        do {
            result = try backend.copyMatching(
                validated(
                    KeychainQuery(
                        itemClass: .genericPassword,
                        service: service,
                        accessGroup: accessGroup,
                        returnAttributes: true,
                        matchLimit: .all
                    )
                )
            )
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "allAccounts returned no items for service=\(service, privacy: .private(mask: .hash))"
            )
            return []
        }
        guard case .items(let items) = result else {
            SwiftyChainLoggers.keychain.error(
                "allAccounts returned unexpected result for service=\(service, privacy: .private(mask: .hash))"
            )
            throw KeychainError.unexpectedData
        }
        return items.compactMap { item in
            guard case .attributes(let attributes) = item else { return nil }
            return attributes.compactMap { attribute in
                if case .account(let account) = attribute { return account }
                return nil
            }.first
        }
    }

    package func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws {
        logKeychainOperationStarted("saveInternetPassword", service: key.server, account: key.account)
        do {
            try backend.add(validated(internetAddQuery(for: key)), data: password.keychainData())
            notify(service: key.server, account: key.account, accessGroup: key.accessGroup, kind: .saved)
            logKeychainOperationSucceeded("saveInternetPassword", service: key.server, account: key.account)
        } catch {
            logKeychainOperationFailed("saveInternetPassword", service: key.server, account: key.account, error: error)
            throw error
        }
    }

    package func loadInternetPassword(for key: InternetPasswordKey) throws -> String {
        logKeychainOperationStarted("loadInternetPassword", service: key.server, account: key.account)
        do {
            let result = try backend.copyMatching(validated(internetIdentityQuery(for: key, returnData: true)))
            guard case .data(let data) = result else {
                SwiftyChainLoggers.keychain.error(
                    "loadInternetPassword returned unexpected result for server=\(key.server, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
                )
                throw KeychainError.unexpectedData
            }
            return try String.fromKeychainData(data)
        } catch KeychainError.itemNotFound {
            SwiftyChainLoggers.keychain.debug(
                "loadInternetPassword returned item not found for server=\(key.server, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
            )
            throw KeychainError.itemNotFound
        } catch {
            logKeychainOperationFailed("loadInternetPassword", service: key.server, account: key.account, error: error)
            throw error
        }
    }

    package func deleteInternetPassword(for key: InternetPasswordKey) throws {
        logKeychainOperationStarted("deleteInternetPassword", service: key.server, account: key.account)
        do {
            try backend.delete(matching: validated(internetIdentityQuery(for: key)))
            notify(service: key.server, account: key.account, accessGroup: key.accessGroup, kind: .deleted)
            logKeychainOperationSucceeded("deleteInternetPassword", service: key.server, account: key.account)
        } catch {
            logKeychainOperationFailed(
                "deleteInternetPassword",
                service: key.server,
                account: key.account,
                error: error
            )
            throw error
        }
    }

    #if Observation
        package func observeKeychainChanges(service: String, accessGroup: String?) -> AsyncStream<KeychainChangeEvent> {
            observers.register(service: service, accessGroup: accessGroup)
        }

        private func notify(service: String, account: String?, accessGroup: String?, kind: KeychainChangeEvent.Kind) {
            observers.emit(
                KeychainChangeEvent(service: service, account: account, kind: kind), accessGroup: accessGroup)
        }
    #else
        private func notify(service: String, account: String?, accessGroup: String?, kind: MutationKind) {}

        private enum MutationKind {
            case saved
            case updated
            case deleted
            case bulkDeleted
        }
    #endif

    // Shared by save and upsert. Logging is left to the caller so an upsert
    // that hits an existing item does not report a failed save.
    private func add<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        try backend.add(validated(addQuery(for: key)), data: value.keychainData())
        notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .saved)
    }

    private func validated(_ query: KeychainQuery) throws -> KeychainQuery {
        try SecureStorageQueryValidator.validate(query, against: backend.capabilities)
        return query
    }

    // Identity-only query: the attributes a backend uses to match an existing
    // item (class + service + account + accessGroup + synchronizable).
    private func identityQuery<T: KeychainStorable>(
        for key: KeychainKey<T>,
        returnData: Bool = false
    ) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable,
            returnData: returnData
        )
    }

    // Full query for adding an item: writes accessibility, label, and comment as
    // attributes alongside the identity fields.
    private func addQuery<T: KeychainStorable>(for key: KeychainKey<T>) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            accessibility: key.accessibility,
            isSynchronizable: key.isSynchronizable,
            label: key.label,
            comment: key.comment
        )
    }

    private func internetIdentityQuery(
        for key: InternetPasswordKey,
        returnData: Bool = false
    ) -> KeychainQuery {
        KeychainQuery(
            itemClass: .internetPassword,
            account: key.account,
            accessGroup: key.accessGroup,
            returnData: returnData,
            server: key.server,
            port: key.port,
            path: key.path,
            internetProtocol: key.protocol,
            authenticationType: key.authenticationType
        )
    }

    private func internetAddQuery(for key: InternetPasswordKey) -> KeychainQuery {
        KeychainQuery(
            itemClass: .internetPassword,
            account: key.account,
            accessGroup: key.accessGroup,
            accessibility: key.accessibility,
            server: key.server,
            port: key.port,
            path: key.path,
            internetProtocol: key.protocol,
            authenticationType: key.authenticationType
        )
    }

    private func logKeychainOperationStarted(_ operation: StaticString, service: String, account: String?) {
        SwiftyChainLoggers.keychain.debug(
            "\(operation) started for service=\(service, privacy: .private(mask: .hash)) account=\(account ?? "<none>", privacy: .private(mask: .hash))"
        )
    }

    private func logKeychainOperationSucceeded(_ operation: StaticString, service: String, account: String?) {
        SwiftyChainLoggers.keychain.debug(
            "\(operation) succeeded for service=\(service, privacy: .private(mask: .hash)) account=\(account ?? "<none>", privacy: .private(mask: .hash))"
        )
    }

    private func logKeychainOperationFailed(
        _ operation: StaticString,
        service: String,
        account: String?,
        error: any Error
    ) {
        let errorName = keychainLogErrorName(for: error)
        if isExpectedOutcome(error) {
            SwiftyChainLoggers.keychain.debug(
                "\(operation) failed for service=\(service, privacy: .private(mask: .hash)) account=\(account ?? "<none>", privacy: .private(mask: .hash)) error=\(errorName, privacy: .public)"
            )
        } else {
            SwiftyChainLoggers.keychain.error(
                "\(operation) failed for service=\(service, privacy: .private(mask: .hash)) account=\(account ?? "<none>", privacy: .private(mask: .hash)) error=\(errorName, privacy: .public)"
            )
        }
    }

    private func logBulkDeleteStarted(query: KeychainDeleteQuery) {
        SwiftyChainLoggers.keychain.debug(
            "deleteAllItems started for service=\(query.service ?? "<all>", privacy: .private(mask: .hash)) accessGroup=\(query.accessGroup ?? "<none>", privacy: .private(mask: .hash)) includeSynchronizable=\(query.includeSynchronizable, privacy: .public) onlySynchronizable=\(query.onlySynchronizable, privacy: .public)"
        )
    }

    private func logBulkDeleteSucceeded(query: KeychainDeleteQuery) {
        SwiftyChainLoggers.keychain.debug(
            "deleteAllItems succeeded for service=\(query.service ?? "<all>", privacy: .private(mask: .hash)) accessGroup=\(query.accessGroup ?? "<none>", privacy: .private(mask: .hash))"
        )
    }

    private func logBulkDeleteFailed(query: KeychainDeleteQuery, error: any Error) {
        let errorName = keychainLogErrorName(for: error)
        if isExpectedOutcome(error) {
            SwiftyChainLoggers.keychain.debug(
                "deleteAllItems failed for service=\(query.service ?? "<all>", privacy: .private(mask: .hash)) accessGroup=\(query.accessGroup ?? "<none>", privacy: .private(mask: .hash)) error=\(errorName, privacy: .public)"
            )
        } else {
            SwiftyChainLoggers.keychain.error(
                "deleteAllItems failed for service=\(query.service ?? "<all>", privacy: .private(mask: .hash)) accessGroup=\(query.accessGroup ?? "<none>", privacy: .private(mask: .hash)) error=\(errorName, privacy: .public)"
            )
        }
    }

    // Failures the caller receives as a KeychainError and can act on are logged at debug
    // level; anything else points at a fault and is logged as an error.
    private func isExpectedOutcome(_ error: any Error) -> Bool {
        (error as? KeychainError)?.isExpectedOutcome ?? false
    }

    private func keychainLogErrorName(for error: any Error) -> String {
        if let keychainError = error as? KeychainError {
            return keychainError.logName
        }
        return String(reflecting: type(of: error))
    }
}
