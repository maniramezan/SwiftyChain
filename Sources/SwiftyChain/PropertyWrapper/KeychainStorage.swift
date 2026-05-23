import Foundation
import Security

/// Synchronous, `@AppStorage`-shaped access to a single optional keychain value.
///
/// Reads and writes go directly to the keychain (not through the ``Keychain`` actor),
/// so writes through `@KeychainStorage` do **not** emit observation events from
/// ``Keychain/observeKeychainChanges(service:accessGroup:)``. Use ``Keychain/shared``
/// directly when you need change notifications.
///
/// The projected value (`$property`) exposes the last ``KeychainError``, if any.
/// Both the wrapped getter and setter are non-mutating, so the wrapper can be
/// stored inside `let` values and read from non-mutating contexts.
@propertyWrapper
public struct KeychainStorage<Value: KeychainStorable>: @unchecked Sendable {
    private let key: KeychainKey<Value>
    private let backend: any SecureStorageBackend
    private let defaultValue: Value?
    private let errorBox: ErrorBox

    public var projectedValue: KeychainError? {
        errorBox.value
    }

    public init(
        _ account: String,
        service: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked,
        isSynchronizable: Bool = false,
        defaultValue: Value? = nil
    ) {
        self.init(
            account,
            service: service,
            backend: AppleKeychainBackend(),
            accessGroup: accessGroup,
            accessibility: accessibility,
            isSynchronizable: isSynchronizable,
            defaultValue: defaultValue
        )
    }

    internal init(
        _ account: String,
        service: String,
        backend: any SecureStorageBackend,
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
        self.backend = backend
        self.defaultValue = defaultValue
        self.errorBox = ErrorBox()
    }

    public var wrappedValue: Value? {
        get {
            do {
                let result = try backend.copyMatching(identityQuery(returnData: true))
                guard case .data(let data) = result else {
                    throw KeychainError.unexpectedData
                }
                errorBox.value = nil
                return try Value.fromKeychainData(data)
            } catch KeychainError.itemNotFound {
                errorBox.value = nil
                return defaultValue
            } catch let error as KeychainError {
                errorBox.value = error
                return defaultValue
            } catch {
                errorBox.value = .unexpectedData
                return defaultValue
            }
        }
        nonmutating set {
            do {
                if let newValue {
                    do {
                        try backend.add(addQuery(), data: newValue.keychainData())
                    } catch KeychainError.duplicateItem {
                        try backend.update(
                            matching: identityQuery(),
                            to: KeychainAttributes(
                                data: try newValue.keychainData(),
                                label: key.label,
                                comment: key.comment,
                                accessibility: key.accessibility
                            )
                        )
                    }
                } else {
                    try backend.delete(matching: identityQuery())
                }
                errorBox.value = nil
            } catch let error as KeychainError {
                errorBox.value = error
            } catch {
                errorBox.value = .unexpectedData
            }
        }
    }

    private func identityQuery(returnData: Bool = false) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: key.service,
            account: key.account,
            accessGroup: key.accessGroup,
            isSynchronizable: key.isSynchronizable,
            returnData: returnData
        )
    }

    private func addQuery() -> KeychainQuery {
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

    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: KeychainError?

        var value: KeychainError? {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }
}
