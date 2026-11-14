import Foundation

/// The platform-neutral implementation behind ``Keychain`` and `InMemoryKeychain`.
///
/// The engine turns public operations into ``KeychainQuery`` values, validates them
/// against the backend's capabilities, calls the ``KeychainBackend``, and emits
/// observation events. Every backend shares this logic, so they behave the same.
package struct KeychainEngine: Sendable {
    package let backend: any KeychainBackend
    #if Observation
        private let observers: KeychainObserverRegistry
    #endif

    package init(backend: any KeychainBackend) {
        self.backend = backend
        #if Observation
            self.observers = KeychainObserverRegistry()
        #endif
    }

    #if Observation
        package init(backend: any KeychainBackend, observers: KeychainObserverRegistry) {
            self.backend = backend
            self.observers = observers
        }
    #endif

    package static func platformDefault(configuration: KeychainConfiguration = .init()) -> Self {
        #if Observation
            Self(backend: PlatformDefaultBackend.make(configuration: configuration), observers: .platformDefault)
        #else
            Self(backend: PlatformDefaultBackend.make(configuration: configuration))
        #endif
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
            let data = try backend.data(matching: validated(identityQuery(for: key), for: .read))
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
            let attributes = try writeAttributes(value, for: key)
            try backend.update(
                matching: validated(identityQuery(for: key), attributes: attributes, for: .update),
                to: attributes
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
            try backend.delete(matching: validated(identityQuery(for: key), for: .delete))
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
            switch query.itemClass.kind {
            case .cryptographicKey:
                try deleteAllCryptoKeys(matching: query)
            case .genericPassword:
                try backend.delete(
                    matching: validated(
                        KeychainQuery(
                            itemClass: query.itemClass,
                            service: query.service,
                            accessGroup: query.accessGroup,
                            isSynchronizable: isSynchronizable
                        ),
                        for: .delete
                    )
                )
            case .internetPassword:
                // An internet password's equivalent of a service is its server.
                try backend.delete(
                    matching: validated(
                        KeychainQuery(
                            itemClass: query.itemClass,
                            accessGroup: query.accessGroup,
                            isSynchronizable: isSynchronizable,
                            server: query.service
                        ),
                        for: .delete
                    )
                )
            }
            if let service = query.service {
                if query.itemClass == .internetPassword {
                    notify(server: service, account: nil, accessGroup: query.accessGroup, kind: .bulkDeleted)
                } else {
                    notify(service: service, account: nil, accessGroup: query.accessGroup, kind: .bulkDeleted)
                }
            }
            logBulkDeleteSucceeded(query: query)
        } catch {
            logBulkDeleteFailed(query: query, error: error)
            throw error
        }
    }

    package func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool {
        do {
            let exists = try backend.contains(matching: validated(identityQuery(for: key), for: .read))
            if !exists {
                SwiftyChainLoggers.keychain.debug(
                    "exists returned false for service=\(key.service, privacy: .private(mask: .hash)) account=\(key.account, privacy: .private(mask: .hash))"
                )
            }
            return exists
        } catch {
            logKeychainOperationFailed("exists", service: key.service, account: key.account, error: error)
            throw error
        }
    }

    package func allAccounts(service: String, accessGroup: String?) throws -> [String] {
        SwiftyChainLoggers.keychain.debug(
            "allAccounts started for service=\(service, privacy: .private(mask: .hash))"
        )
        do {
            let accounts = try backend.accounts(
                matching: validated(
                    KeychainQuery(itemClass: .genericPassword, service: service, accessGroup: accessGroup),
                    for: .read
                )
            )
            SwiftyChainLoggers.keychain.debug(
                "allAccounts found count=\(accounts.count, privacy: .public) for service=\(service, privacy: .private(mask: .hash))"
            )
            return accounts
        } catch {
            logKeychainOperationFailed("allAccounts", service: service, account: nil, error: error)
            throw error
        }
    }

    package func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws {
        logKeychainOperationStarted("saveInternetPassword", service: key.server, account: key.account)
        do {
            let attributes = KeychainAttributes(
                data: try password.keychainData(), accessibility: key.accessibility, accessControl: key.accessControl)
            try backend.add(
                validated(internetIdentityQuery(for: key), attributes: attributes, for: .add),
                attributes: attributes
            )
            notify(server: key.server, account: key.account, accessGroup: key.accessGroup, kind: .saved)
            logKeychainOperationSucceeded("saveInternetPassword", service: key.server, account: key.account)
        } catch {
            logKeychainOperationFailed("saveInternetPassword", service: key.server, account: key.account, error: error)
            throw error
        }
    }

    package func loadInternetPassword(for key: InternetPasswordKey) throws -> String {
        logKeychainOperationStarted("loadInternetPassword", service: key.server, account: key.account)
        do {
            let data = try backend.data(matching: validated(internetIdentityQuery(for: key), for: .read))
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
            try backend.delete(matching: validated(internetIdentityQuery(for: key), for: .delete))
            notify(server: key.server, account: key.account, accessGroup: key.accessGroup, kind: .deleted)
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

        package func observeKeychainChanges(server: String, accessGroup: String?) -> AsyncStream<KeychainChangeEvent> {
            observers.register(server: server, accessGroup: accessGroup)
        }

        private func notify(server: String, account: String?, accessGroup: String?, kind: KeychainChangeEvent.Kind) {
            observers.emit(KeychainChangeEvent(server: server, account: account, kind: kind), accessGroup: accessGroup)
        }

        private func notify(service: String, account: String?, accessGroup: String?, kind: KeychainChangeEvent.Kind) {
            observers.emit(
                KeychainChangeEvent(service: service, account: account, kind: kind), accessGroup: accessGroup)
        }
    #else
        private func notify(server: String, account: String?, accessGroup: String?, kind: MutationKind) {}

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
        let attributes = try writeAttributes(value, for: key)
        try backend.add(validated(identityQuery(for: key), attributes: attributes, for: .add), attributes: attributes)
        notify(service: key.service, account: key.account, accessGroup: key.accessGroup, kind: .saved)
    }

    // Cryptographic keys live behind KeychainCryptoBackend and have no service, so a
    // bulk delete of them selects keys by access group alone.
    private func deleteAllCryptoKeys(matching query: KeychainDeleteQuery) throws {
        _ = try validated(KeychainQuery(itemClass: query.itemClass, accessGroup: query.accessGroup), for: .delete)
        if query.service != nil {
            throw invalidArgument(
                "Cryptographic keys have no service. Delete them by access group, or pass no service"
            )
        }
        if query.onlySynchronizable {
            throw invalidArgument("SwiftyChain stores cryptographic keys as local items, so none are synchronizable")
        }
        #if Cryptography && canImport(Security)
            try cryptoBackend().deleteAllCryptoKeys(accessGroup: query.accessGroup)
        #else
            SwiftyChainLoggers.keychain.debug("Crypto key bulk delete requested without a crypto backend")
            throw KeychainError.platformUnsupported("Cryptographic keys are not supported by this keychain backend")
        #endif
    }

    package func invalidArgument(_ message: String) -> KeychainError {
        SwiftyChainLoggers.keychain.debug("Rejected invalid argument: \(message, privacy: .public)")
        return .invalidArgument(message)
    }

    private func validated(
        _ query: KeychainQuery,
        attributes: KeychainAttributes? = nil,
        for operation: KeychainOperation
    ) throws -> KeychainQuery {
        if query.isSynchronizable == true, attributes?.accessibility?.isThisDeviceOnly == true {
            throw invalidArgument("A synchronizable item can't use a ThisDeviceOnly accessibility")
        }
        if query.isSynchronizable == true, attributes?.accessControl != nil {
            throw invalidArgument("A synchronizable item can't use access control")
        }
        try KeychainQueryValidator.validate(
            query, attributes: attributes, for: operation, against: backend.capabilities)
        return query
    }

    // The attributes a backend uses to match an existing item: class, service,
    // account, access group, and synchronizable. Writes go in `writeAttributes`.
    private func identityQuery<T: KeychainStorable>(for key: KeychainKey<T>) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable
        )
    }

    private func writeAttributes<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws
        -> KeychainAttributes
    {
        KeychainAttributes(
            data: try value.keychainData(),
            label: key.label,
            comment: key.comment,
            accessibility: key.accessibility,
            accessControl: key.accessControl
        )
    }

    private func internetIdentityQuery(for key: InternetPasswordKey) -> KeychainQuery {
        KeychainQuery(
            itemClass: .internetPassword,
            account: key.account,
            accessGroup: key.accessGroup,
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
