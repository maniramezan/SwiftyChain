import Foundation
import SwiftyChain
import Synchronization

#if Cryptography && canImport(Security)
    import Security
#endif

/// A `KeychainBackend` that keeps items in memory, for tests.
///
/// It follows the same matching rules as the platform backends: a `nil` query attribute
/// matches any stored value, and a query that leaves `isSynchronizable` unset matches
/// both synchronizable and local items. Pass it to `Keychain(backend:)` or
/// `KeychainStorage(_:service:backend:)` so tests run the same engine as production
/// without touching the system keychain:
///
/// ```swift
/// import SwiftyChain
/// import SwiftyChainTesting
///
/// let backend = InMemoryKeychainBackend()
/// let storage = KeychainStorage<String>(
///     "auth-token",
///     service: "com.example.app",
///     backend: backend
/// )
///
/// storage.wrappedValue = "secret"
/// assert(storage.wrappedValue == "secret")
/// ```
///
/// Each instance starts empty. Create a fresh one per test to guarantee isolation.
///
/// ## Thread safety
///
/// `InMemoryKeychainBackend` is `Sendable` and serializes concurrent reads and
/// writes, so it is safe to share across threads or tasks.
public final class InMemoryKeychainBackend: KeychainBackend, Sendable {
    private struct Item: Sendable {
        let query: KeychainQuery
        var accessibility: KeychainAccessibility?
        var accessControl: KeychainAccessControl?
        var label: String?
        var comment: String?
        var data: Data

        func hasSameIdentity(as other: KeychainQuery) -> Bool {
            query.itemClass == other.itemClass
                && query.service == other.service
                && query.account == other.account
                && query.accessGroup == other.accessGroup
                && (query.isSynchronizable ?? false) == (other.isSynchronizable ?? false)
                && query.server == other.server
                && query.port == other.port
                && query.path == other.path
                && query.internetProtocol == other.internetProtocol
                && query.authenticationType == other.authenticationType
        }

        func matches(_ other: KeychainQuery) -> Bool {
            query.itemClass == other.itemClass
                && Self.matches(query.service, other.service)
                && Self.matches(query.account, other.account)
                && Self.matches(query.accessGroup, other.accessGroup)
                && Self.matches(query.isSynchronizable ?? false, other.isSynchronizable)
                && Self.matches(query.server, other.server)
                && Self.matches(query.port, other.port)
                && Self.matches(query.path, other.path)
                && Self.matches(query.internetProtocol, other.internetProtocol)
                && Self.matches(query.authenticationType, other.authenticationType)
        }

        private static func matches<Value: Equatable>(_ stored: Value?, _ requested: Value?) -> Bool {
            guard let requested else { return true }
            return stored == requested
        }
    }

    /// The capabilities this backend reports, which `Keychain` validates every query against.
    public let capabilities: KeychainBackendCapabilities

    private let items = Mutex<[Item]>([])

    /// Creates a new, empty in-memory backend.
    ///
    /// - Parameter capabilities: The features to report. Pass fewer than the default to
    ///   reproduce a platform's restrictions, such as Linux's. Defaults to every
    ///   capability this platform can store.
    public init(capabilities: KeychainBackendCapabilities = InMemoryKeychainBackend.defaultCapabilities) {
        self.capabilities = capabilities
    }

    /// Every capability the in-memory backend can store on this platform. Cryptographic
    /// keys need the `cryptography` trait and the Security framework.
    public static var defaultCapabilities: KeychainBackendCapabilities {
        #if Cryptography && canImport(Security)
            .all
        #else
            KeychainBackendCapabilities.all.subtracting(.cryptoKeys)
        #endif
    }

    public func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {
        let item = Item(
            query: query,
            accessibility: attributes.accessibility,
            accessControl: attributes.accessControl,
            label: attributes.label,
            comment: attributes.comment,
            data: attributes.data ?? Data()
        )
        try items.withLock { items in
            if items.contains(where: { $0.hasSameIdentity(as: query) }) {
                throw KeychainError.duplicateItem
            }
            items.append(item)
        }
    }

    public func data(matching query: KeychainQuery) throws -> Data {
        guard let item = items.withLock({ items in items.first { $0.matches(query) } }) else {
            throw KeychainError.itemNotFound
        }
        return item.data
    }

    public func contains(matching query: KeychainQuery) throws -> Bool {
        items.withLock { items in items.contains { $0.matches(query) } }
    }

    public func accounts(matching query: KeychainQuery) throws -> [String] {
        items.withLock { items in items.filter { $0.matches(query) }.compactMap(\.query.account) }
    }

    public func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        try items.withLock { items in
            let indices = items.indices.filter { items[$0].matches(query) }
            guard !indices.isEmpty else {
                throw KeychainError.itemNotFound
            }
            for index in indices {
                if let data = attributes.data {
                    items[index].data = data
                }
                if let label = attributes.label {
                    items[index].label = label
                }
                if let comment = attributes.comment {
                    items[index].comment = comment
                }
                if let accessControl = attributes.accessControl {
                    items[index].accessControl = accessControl
                }
                if let accessibility = attributes.accessibility {
                    items[index].accessibility = accessibility
                }
            }
        }
    }

    public func delete(matching query: KeychainQuery) throws {
        items.withLock { items in items.removeAll { $0.matches(query) } }
    }

    #if Cryptography && canImport(Security)
        private struct CryptoItem: Sendable {
            let tag: String
            let accessGroup: String?
            var key: StoredSecKey
            var accessibility: KeychainAccessibility?
            var accessControl: KeychainAccessControl?

            /// Like the platform keychain, a query without an access group matches a key
            /// in any group.
            func matches(_ query: CryptoKeyQuery) -> Bool {
                tag == query.tag && (query.accessGroup == nil || accessGroup == query.accessGroup)
            }
        }

        private let cryptoKeys = Mutex<[CryptoItem]>([])
    #endif
}

#if Cryptography && canImport(Security)
    extension InMemoryKeychainBackend: KeychainCryptoBackend {
        public func addCryptoKey(_ key: SecKey, query: CryptoKeyQuery, attributes: CryptoKeyAttributes) throws {
            try cryptoKeys.withLock { keys in
                if keys.contains(where: { $0.matches(query) }) {
                    throw KeychainError.duplicateItem
                }
                keys.append(
                    CryptoItem(
                        tag: query.tag, accessGroup: query.accessGroup, key: StoredSecKey(key),
                        accessibility: attributes.accessibility, accessControl: attributes.accessControl))
            }
        }

        /// Replaces every matching key, keeping the stored values `attributes` leaves `nil`.
        ///
        /// - Throws: `KeychainError.invalidArgument` when the replacement's type, class,
        ///   or size differs from a stored key's, as the platform keychain does.
        public func updateCryptoKey(_ key: SecKey, query: CryptoKeyQuery, attributes: CryptoKeyAttributes) throws {
            let replacementShape = Self.shape(of: key)
            try cryptoKeys.withLock { keys in
                let indices = keys.indices.filter { keys[$0].matches(query) }
                guard !indices.isEmpty else { throw KeychainError.itemNotFound }
                guard indices.allSatisfy({ Self.shape(of: keys[$0].key.rawValue) == replacementShape }) else {
                    throw KeychainError.invalidArgument(
                        "The replacement key's type, class, or size differs from the stored key; delete the stored key first"
                    )
                }
                for index in indices {
                    keys[index].key = StoredSecKey(key)
                    if let accessibility = attributes.accessibility { keys[index].accessibility = accessibility }
                    if let accessControl = attributes.accessControl { keys[index].accessControl = accessControl }
                }
            }
        }

        public func loadCryptoKey(query: CryptoKeyQuery) throws -> SecKey {
            guard let stored = cryptoKeys.withLock({ keys in keys.first { $0.matches(query) } }) else {
                throw KeychainError.itemNotFound
            }
            return stored.key.rawValue
        }

        public func deleteCryptoKey(query: CryptoKeyQuery) throws {
            cryptoKeys.withLock { keys in keys.removeAll { $0.matches(query) } }
        }

        public func deleteAllCryptoKeys(accessGroup: String?) throws {
            cryptoKeys.withLock { keys in
                keys.removeAll { accessGroup == nil || $0.accessGroup == accessGroup }
            }
        }

        private static func shape(of key: SecKey) -> [String?] {
            let attributes = SecKeyCopyAttributes(key) as? [String: Any] ?? [:]
            return [kSecAttrKeyType, kSecAttrKeyClass, kSecAttrKeySizeInBits].map { name in
                switch attributes[name as String] {
                case let number as NSNumber: number.stringValue
                case let string as String: string
                default: nil
                }
            }
        }
    }
#endif
