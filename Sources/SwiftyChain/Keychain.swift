import Foundation

/// Actor-isolated public API for keychain operations.
public actor Keychain {
    public static let shared = Keychain()

    private enum MutationKind: Sendable {
        case saved
        case updated
        case deleted
        case bulkDeleted
    }

    private let backend: any SecureStorageBackend
    #if Observation
        private var observers: [UUID: Observer] = [:]
    #endif

    public init() {
        self.backend = AppleKeychainBackend()
    }

    internal init(backend: any SecureStorageBackend) {
        self.backend = backend
    }

    public func save<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        try backend.add(query(for: key), data: value.keychainData())
        notify(service: key.service, account: key.account, kind: .saved)
    }

    public func load<T: KeychainStorable>(key: KeychainKey<T>) throws -> T {
        let result = try backend.copyMatching(query(for: key, returnData: true))
        guard case .data(let data) = result else {
            throw KeychainError.unexpectedData
        }
        return try T.fromKeychainData(data)
    }

    public func loadIfPresent<T: KeychainStorable>(key: KeychainKey<T>) throws -> T? {
        do {
            return try load(key: key)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

    public func update<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        try backend.update(
            matching: query(for: key),
            to: KeychainAttributes(
                data: try value.keychainData(),
                label: key.label,
                comment: key.comment,
                accessibility: key.accessibility
            )
        )
        notify(service: key.service, account: key.account, kind: .updated)
    }

    public func upsert<T: KeychainStorable>(_ value: T, for key: KeychainKey<T>) throws {
        do {
            try save(value, for: key)
        } catch KeychainError.duplicateItem {
            try update(value, for: key)
        }
    }

    public func delete<T: KeychainStorable>(key: KeychainKey<T>) throws {
        try backend.delete(matching: query(for: key))
        notify(service: key.service, account: key.account, kind: .deleted)
    }

    public func deleteAll(service: String, accessGroup: String? = nil) throws {
        try deleteAllItems(matching: .allItems(service: service, accessGroup: accessGroup))
    }

    public func deleteAllSynchronizable(service: String, accessGroup: String? = nil) throws {
        try deleteAllItems(matching: .synchronizableItems(service: service, accessGroup: accessGroup))
    }

    public func deleteAllItems(matching query: KeychainDeleteQuery) throws {
        let isSynchronizable: Bool? =
            if query.onlySynchronizable {
                true
            } else if query.includeSynchronizable {
                nil
            } else {
                false
            }
        try backend.delete(
            matching: KeychainQuery(
                itemClass: query.itemClass,
                service: query.service,
                accessGroup: query.accessGroup,
                isSynchronizable: isSynchronizable
            )
        )
        if let service = query.service {
            notify(service: service, account: nil, kind: .bulkDeleted)
        }
    }

    public func exists<T: KeychainStorable>(key: KeychainKey<T>) throws -> Bool {
        do {
            _ = try backend.copyMatching(query(for: key))
            return true
        } catch KeychainError.itemNotFound {
            return false
        }
    }

    public func allAccounts(service: String, accessGroup: String? = nil) throws -> [String] {
        let result = try backend.copyMatching(
            KeychainQuery(
                itemClass: .genericPassword,
                service: service,
                accessGroup: accessGroup,
                returnAttributes: true,
                matchLimit: .all
            )
        )
        guard case .items(let items) = result else {
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

    public func saveInternetPassword(_ password: String, for key: InternetPasswordKey) throws {
        let query = internetQuery(for: key, accessibility: key.accessibility)
        try backend.add(query, data: password.keychainData())
        notify(service: key.server, account: key.account, kind: .saved)
    }

    public func loadInternetPassword(for key: InternetPasswordKey) throws -> String {
        let result = try backend.copyMatching(internetQuery(for: key, returnData: true))
        guard case .data(let data) = result else {
            throw KeychainError.unexpectedData
        }
        return try String.fromKeychainData(data)
    }

    public func deleteInternetPassword(for key: InternetPasswordKey) throws {
        try backend.delete(matching: internetQuery(for: key))
        notify(service: key.server, account: key.account, kind: .deleted)
    }

    #if Observation
        public func observeKeychainChanges(
            service: String,
            accessGroup: String? = nil
        ) -> AsyncStream<KeychainChangeEvent> {
            let id = UUID()
            return AsyncStream { continuation in
                observers[id] = Observer(service: service, accessGroup: accessGroup, continuation: continuation)
                continuation.onTermination = { [weak self] _ in
                    Task { await self?.removeObserver(id: id) }
                }
            }
        }

        private struct Observer: Sendable {
            let service: String
            let accessGroup: String?
            let continuation: AsyncStream<KeychainChangeEvent>.Continuation
        }

        private func removeObserver(id: UUID) {
            observers.removeValue(forKey: id)
        }

        private func notify(service: String, account: String?, kind: MutationKind) {
            let eventKind: KeychainChangeEvent.Kind =
                switch kind {
                case .saved: .saved
                case .updated: .updated
                case .deleted: .deleted
                case .bulkDeleted: .bulkDeleted
                }
            let event = KeychainChangeEvent(service: service, account: account, kind: eventKind)
            for observer in observers.values where observer.service == service {
                observer.continuation.yield(event)
            }
        }
    #else
        private func notify(service: String, account: String?, kind: MutationKind) {}
    #endif

    private func query<T: KeychainStorable>(
        for key: KeychainKey<T>,
        returnData: Bool = false,
        returnAttributes: Bool = false
    ) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            accessibility: key.accessibility,
            isSynchronizable: key.isSynchronizable,
            returnData: returnData,
            returnAttributes: returnAttributes,
            label: key.label,
            comment: key.comment
        )
    }

    private func internetQuery(
        for key: InternetPasswordKey,
        returnData: Bool = false,
        accessibility: KeychainAccessibility? = nil
    ) -> KeychainQuery {
        KeychainQuery(
            itemClass: .internetPassword,
            account: key.account,
            accessGroup: key.accessGroup,
            accessibility: accessibility,
            returnData: returnData,
            server: key.server,
            port: key.port,
            path: key.path,
            internetProtocol: key.protocol,
            authenticationType: key.authenticationType
        )
    }
}
