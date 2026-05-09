import Security

/// Synchronous `@AppStorage`-style access to optional keychain values.
///
/// - Important: `@KeychainStorage` bypasses the `Keychain` actor and accesses the keychain directly.
///   This means writes through `@KeychainStorage` will **not** trigger observation events from
///   `Keychain/observeKeychainChanges(service:accessGroup:)`. If you need change notifications,
///   use `Keychain.shared` methods instead.
@propertyWrapper
public struct KeychainStorage<Value: KeychainStorable>: Sendable {
    private let key: KeychainKey<Value>
    private let backend: any SecureStorageBackend
    private let defaultValue: Value?

    public private(set) var projectedValue: KeychainError?

    public init(
        _ account: String,
        service: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked,
        isSynchronizable: Bool = false,
        defaultValue: Value? = nil
    ) {
        self.key = KeychainKey(
            service: service,
            account: account,
            accessGroup: accessGroup,
            accessibility: accessibility,
            isSynchronizable: isSynchronizable
        )
        self.backend = AppleKeychainBackend()
        self.defaultValue = defaultValue
        self.projectedValue = nil
    }

    public var wrappedValue: Value? {
        mutating get {
            do {
                let result = try backend.copyMatching(query(returnData: true))
                guard case .data(let data) = result else {
                    throw KeychainError.unexpectedData
                }
                projectedValue = nil
                return try Value.fromKeychainData(data)
            } catch KeychainError.itemNotFound {
                projectedValue = nil
                return defaultValue
            } catch let error as KeychainError {
                projectedValue = error
                return defaultValue
            } catch {
                projectedValue = .unexpectedData
                return defaultValue
            }
        }
        mutating set {
            do {
                if let newValue {
                    do {
                        try backend.add(query(), data: newValue.keychainData())
                    } catch KeychainError.duplicateItem {
                        try backend.update(
                            matching: query(),
                            to: KeychainAttributes(
                                data: try newValue.keychainData(),
                                label: key.label,
                                comment: key.comment,
                                accessibility: key.accessibility
                            )
                        )
                    }
                } else {
                    try backend.delete(matching: query())
                }
                projectedValue = nil
            } catch let error as KeychainError {
                projectedValue = error
            } catch {
                projectedValue = .unexpectedData
            }
        }
    }

    private func query(returnData: Bool = false) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            accessibility: key.accessibility,
            isSynchronizable: key.isSynchronizable,
            returnData: returnData
        )
    }
}
