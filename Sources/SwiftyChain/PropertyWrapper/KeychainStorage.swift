import Foundation
import Synchronization

/// Synchronous, `@AppStorage`-shaped access to a single optional keychain value.
///
/// Reads and writes run synchronously on the caller's thread, outside the ``Keychain``
/// actor, through the same engine and validation as ``Keychain``.
///
/// The projected value (`$property`) exposes the last ``KeychainError``, if any.
/// Both the wrapped getter and setter are non-mutating, so the wrapper can be
/// stored inside `let` values and read from non-mutating contexts.
@propertyWrapper
public struct KeychainStorage<Value: KeychainStorable>: Sendable {
    private let key: KeychainKey<Value>
    private let engine: KeychainEngine
    private let errorBox: ErrorBox

    /// The last ``KeychainError`` that occurred during a get or set, or `nil` if the last operation succeeded.
    ///
    /// Access this via the projected value syntax:
    /// ```swift
    /// import OSLog
    ///
    /// let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")
    ///
    /// if let error = $token {
    ///     logger.error("Keychain operation failed: \(error.logName, privacy: .public)")
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
    ///   - accessibility: Controls when the item is accessible. Defaults to `nil`, which uses
    ///     the platform default for a new item and keeps an existing item's policy.
    ///   - accessControl: Authentication required to access the item. Defaults to `nil`.
    ///   - isSynchronizable: Pass `true` to sync this item via iCloud Keychain. Defaults to `false`.
    ///     Apple platforms only; on Linux, `true` makes operations throw ``KeychainError/platformUnsupported(_:)``.
    ///   - configuration: Selects the macOS store. Defaults to the legacy login keychain.
    public init(
        _ account: String,
        service: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility? = nil,
        accessControl: KeychainAccessControl? = nil,
        isSynchronizable: Bool = false,
        configuration: KeychainConfiguration = .init()
    ) {
        self.key = KeychainKey(
            service: service, account: account, accessGroup: accessGroup,
            accessibility: accessibility, accessControl: accessControl, isSynchronizable: isSynchronizable)
        self.engine = .platformDefault(configuration: configuration)
        self.errorBox = ErrorBox()
    }

    /// Creates a property wrapper that stores its value in a custom ``KeychainBackend``.
    ///
    /// - Parameters:
    ///   - account: The account identifier for this keychain item.
    ///   - service: The service name that groups related items.
    ///   - backend: The storage that receives every read and write, such as
    ///     `InMemoryKeychainBackend` in tests.
    ///   - accessGroup: The access group for sharing across apps. Defaults to `nil`.
    ///   - accessibility: Controls when the item is accessible. Defaults to `nil`, the platform default.
    ///   - accessControl: Authentication required to access the item. Defaults to `nil`.
    ///   - isSynchronizable: Pass `true` to sync this item via iCloud Keychain. Defaults to `false`.
    public init(
        _ account: String,
        service: String,
        backend: any KeychainBackend,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility? = nil,
        accessControl: KeychainAccessControl? = nil,
        isSynchronizable: Bool = false
    ) {
        self.key = KeychainKey(
            service: service,
            account: account,
            accessGroup: accessGroup,
            accessibility: accessibility, accessControl: accessControl,
            isSynchronizable: isSynchronizable
        )
        self.engine = KeychainEngine(backend: backend)
        self.errorBox = ErrorBox()
    }

    /// The current keychain value, or `nil` when absent or on error.
    ///
    /// Setting this property to a non-`nil` value creates or updates the keychain item;
    /// setting it to `nil` deletes the item. Both operations are non-mutating, so this
    /// wrapper can be declared with `let` or used from non-mutating contexts.
    ///
    /// If an error occurs during get or set, it is captured in ``projectedValue``.
    public var wrappedValue: Value? {
        get {
            let result = Result { try engine.loadIfPresent(key: key) }
            errorBox.record(result)
            return try? result.get()
        }
        nonmutating set {
            errorBox.record(
                Result {
                    if let newValue {
                        try engine.upsert(newValue, for: key)
                    } else {
                        try engine.delete(key: key)
                    }
                }
            )
        }
    }

    private final class ErrorBox: Sendable {
        private let storage = Mutex<KeychainError?>(nil)

        var value: KeychainError? {
            storage.withLock { $0 }
        }

        // The engine has already logged the failure. An error that isn't a
        // KeychainError, such as one thrown by a custom KeychainStorable, is
        // reported as unexpected data.
        func record<Success>(_ result: Result<Success, any Error>) {
            let error: KeychainError? =
                switch result {
                case .success: nil
                case .failure(let error as KeychainError): error
                case .failure: .unexpectedData
                }
            storage.withLock { $0 = error }
        }
    }
}
