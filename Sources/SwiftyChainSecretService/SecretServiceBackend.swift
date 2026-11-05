#if os(Linux)
    import Foundation
    import SwiftyChainCore

    /// The ``SecureStorageBackend`` for Linux, backed by the freedesktop Secret Service
    /// (GNOME Keyring, KWallet, or any other provider) through libsecret.
    ///
    /// libsecret is loaded at runtime, so nothing is needed at build time. When libsecret,
    /// a D-Bus session bus, or a Secret Service provider is missing, every operation
    /// throws ``KeychainError/platformUnsupported(_:)``. There is no plaintext fallback.
    ///
    /// Apple-only options behave as follows:
    /// - Synchronizable items are rejected; the backend doesn't declare
    ///   ``SecureStorageCapabilities/synchronizable``.
    /// - Access groups are stored as an attribute. They namespace items but don't isolate
    ///   them: any program running as the same user can read an unlocked keyring.
    /// - Accessibility policies and comments are not stored.
    package struct SecretServiceBackend: SecureStorageBackend {
        package let capabilities: SecureStorageCapabilities = [.accessGroups, .internetPasswords]

        private let client: SecretServiceClient

        package init(timeout: Duration = .seconds(30)) {
            self.client = SecretServiceClient(timeout: timeout)
        }

        package func add(_ query: KeychainQuery, data: Data) throws {
            let identity = SecretServiceAttributes.identity(for: query)
            guard try client.search(identity, loadSecrets: false).isEmpty else {
                SwiftyChainLoggers.backend.debug("Secret Service add found an existing item")
                throw KeychainError.duplicateItem
            }
            try client.store(identity, label: SecretServiceAttributes.label(for: query), data: data)
        }

        package func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
            let matching = SecretServiceAttributes.matching(query)
            if query.matchLimit == .one, query.returnData {
                guard let data = try client.lookup(matching) else {
                    throw KeychainError.itemNotFound
                }
                return .data(data)
            }

            let items = try client.search(matching, loadSecrets: false)
            guard let first = items.first else {
                throw KeychainError.itemNotFound
            }
            if query.matchLimit == .all {
                return .items(
                    items.map { .attributes(SecretServiceAttributes.keychainAttributes(from: $0.attributes)) })
            }
            if query.returnAttributes {
                return .attributes(SecretServiceAttributes.keychainAttributes(from: first.attributes))
            }
            return .attributes([])
        }

        package func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
            let matching = SecretServiceAttributes.matching(query)
            let items = try client.search(matching, loadSecrets: attributes.data == nil)
            guard !items.isEmpty else {
                throw KeychainError.itemNotFound
            }
            for item in items {
                guard let data = attributes.data ?? item.secret else {
                    SwiftyChainLoggers.backend.error("Secret Service update could not read the existing secret")
                    throw KeychainError.unexpectedData
                }
                // Storing with the item's exact attribute set replaces that item in place.
                try client.store(
                    SecretServiceItemQuery(schema: matching.schema, attributes: item.attributes),
                    label: attributes.label ?? item.label,
                    data: data
                )
            }
        }

        package func delete(matching query: KeychainQuery) throws {
            try client.clear(SecretServiceAttributes.matching(query))
        }
    }
#endif
