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
    private let backend: any KeychainBackend
    private let defaultValue: Value?
    private let errorBox: ErrorBox

    /// The last ``KeychainError`` that occurred during a get or set, or `nil` if the last operation succeeded.
    ///
    /// Access this via the projected value syntax:
    /// ```swift
    /// if let error = $token {
    ///     print("Keychain error:", error)
    /// }
    /// ```
    public var projectedValue: KeychainError? {
        errorBox.value
    }

    /// Creates a keychain-backed property wrapper.
    ///
    /// - Parameters:
    ///   - account: The account identifier for this keychain item.
    ///   - service: The service name that groups related items (e.g., your app's bundle ID).
    ///   - accessGroup: The access group for sharing across apps. Defaults to `nil`.
    ///   - accessibility: Controls when the item is accessible. Defaults to ``KeychainAccessibility/whenUnlocked``.
    ///   - isSynchronizable: Pass `true` to sync this item via iCloud Keychain. Defaults to `false`.
    ///   - defaultValue: The value returned when no item exists in the keychain. Defaults to `nil`.
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

    public init(
        _ account: String,
        service: String,
        backend: any KeychainBackend,
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

    /// The current keychain value, or `defaultValue` (typically `nil`) when absent or on error.
    ///
    /// Setting this property to a non-`nil` value creates or updates the keychain item;
    /// setting it to `nil` deletes the item. Both operations are non-mutating, so this
    /// wrapper can be declared with `let` or used from non-mutating contexts.
    ///
    /// If an error occurs during get or set, it is captured in ``projectedValue``.
    public var wrappedValue: Value? {
        get {
            do {
                let data = try backend.load(
                    service: key.service,
                    account: key.account,
                    accessGroup: key.accessGroup,
                    isSynchronizable: key.isSynchronizable
                )
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
                        try backend.save(
                            try newValue.keychainData(),
                            service: key.service,
                            account: key.account,
                            accessGroup: key.accessGroup,
                            accessibility: key.accessibility,
                            isSynchronizable: key.isSynchronizable,
                            label: key.label,
                            comment: key.comment
                        )
                    } catch KeychainError.duplicateItem {
                        try backend.update(
                            try newValue.keychainData(),
                            service: key.service,
                            account: key.account,
                            accessGroup: key.accessGroup,
                            accessibility: key.accessibility,
                            isSynchronizable: key.isSynchronizable,
                            label: key.label,
                            comment: key.comment
                        )
                    }
                } else {
                    try backend.delete(
                        service: key.service,
                        account: key.account,
                        accessGroup: key.accessGroup,
                        isSynchronizable: key.isSynchronizable
                    )
                }
                errorBox.value = nil
            } catch let error as KeychainError {
                errorBox.value = error
            } catch {
                errorBox.value = .unexpectedData
            }
        }
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
