#if os(Linux)
    import Foundation
    import SwiftyChainCore

    /// The ``KeychainBackend`` for Linux, backed by the freedesktop Secret Service
    /// (GNOME Keyring, KWallet, or any other provider) through libsecret.
    ///
    /// libsecret is loaded at runtime, so nothing is needed at build time. When libsecret,
    /// a D-Bus session bus, or a Secret Service provider is missing, every operation
    /// throws ``KeychainError/platformUnsupported(_:)``. There is no plaintext fallback.
    ///
    /// Apple-only options behave as follows:
    /// - Synchronizable items are rejected; the backend doesn't declare
    ///   ``KeychainBackendCapabilities/synchronizable``.
    /// - Access groups are stored as an attribute. They namespace items but don't isolate
    ///   them: any program running as the same user can read an unlocked keyring.
    /// - Accessibility policies and comments are not stored.
    package struct SecretServiceBackend: KeychainBackend {
        package let capabilities: KeychainBackendCapabilities = [.accessGroups, .internetPasswords]

        private let client: SecretServiceClient

        package init(timeout: Duration = .seconds(30)) {
            self.client = SecretServiceClient(timeout: timeout)
        }

        package func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {
            try client.add(
                SecretServiceAttributes.identity(for: query),
                label: SecretServiceAttributes.label(for: query, custom: attributes.label),
                data: attributes.data ?? Data()
            )
        }

        package func data(matching query: KeychainQuery) throws -> Data {
            guard let data = try client.lookup(SecretServiceAttributes.matching(query)) else {
                throw KeychainError.itemNotFound
            }
            return data
        }

        package func contains(matching query: KeychainQuery) throws -> Bool {
            try !client.search(SecretServiceAttributes.matching(query), loadSecrets: false).isEmpty
        }

        package func accounts(matching query: KeychainQuery) throws -> [String] {
            try client.search(SecretServiceAttributes.matching(query), loadSecrets: false)
                .compactMap { $0.attributes["account"] }
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
        /// The backend doesn't declare ``KeychainBackendCapabilities/unscopedBulkDelete``,
        /// so callers reject a delete that would reach other SwiftyChain apps' items
        /// before it gets here.
        package func delete(matching query: KeychainQuery) throws {
            let matching = try SecretServiceAttributes.matching(query)
            try client.clear(matching)
        }
    }
#endif
