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
            try client.add(
                SecretServiceAttributes.identity(for: query),
                label: SecretServiceAttributes.label(for: query),
                data: data
            )
        }

        package func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
            let matching = try SecretServiceAttributes.matching(query)
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
            try client.replace(
                SecretServiceAttributes.matching(query),
                label: attributes.label,
                data: attributes.data
            )
        }

        /// Deletes matching items. Succeeds when nothing matches.
        ///
        /// Every app built on SwiftyChain stores items under the same schemas, and the
        /// Secret Service has no app sandbox to scope a query the way Apple's keychain
        /// does. A delete must therefore name a non-empty service, server, or access
        /// group, or one exact item; otherwise it would remove other SwiftyChain apps'
        /// items too. See ``SecretServiceAttributes/isScopedForDeletion(_:)``.
        package func delete(matching query: KeychainQuery) throws {
            let matching = try SecretServiceAttributes.matching(query)
            guard SecretServiceAttributes.isScopedForDeletion(matching) else {
                SwiftyChainLoggers.backend.debug(
                    "Secret Service rejected an unscoped delete for schema=\(matching.schema.name, privacy: .public)"
                )
                throw KeychainError.platformUnsupported(
                    "Deleting without a service, server, or access group is not supported by the Secret Service backend"
                )
            }
            try client.clear(matching)
        }
    }
#endif
