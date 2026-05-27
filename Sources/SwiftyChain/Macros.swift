/// Creates a compile-time-validated ``KeychainKey`` expression.
///
/// The macro validates that all string arguments are literals at compile time and
/// expands to a `KeychainKey<Value>` constant with zero runtime overhead.
///
/// ```swift
/// let key: KeychainKey<String> = #keychainKey(
///     service: "com.example.app",
///     account: "auth-token"
/// )
/// ```
@freestanding(expression)
public macro keychainKey<Value: KeychainStorable>(
    service: String,
    account: String,
    accessGroup: String? = nil,
    accessibility: KeychainAccessibility = .whenUnlocked,
    isSynchronizable: Bool = false,
    label: String? = nil,
    comment: String? = nil
) -> KeychainKey<Value> = #externalMacro(module: "SwiftyChainMacros", type: "KeychainKeyMacro")

/// Synthesizes keychain-backed storage for an optional property.
///
/// Apply `@KeychainItem` to a `var` property. The macro generates an `async throws`
/// getter and a peer `setXxx(_:)` async method that reads from and writes to the
/// keychain. The property type must conform to ``KeychainStorable``.
///
/// - Reads return `nil` when the item is absent.
/// - Passing `nil` to the setter deletes the item.
///
/// ```swift
/// import OSLog
///
/// class AppSecrets {
///     @KeychainItem("token", service: "com.example.app")
///     var authToken: String?
/// }
///
/// let secrets = AppSecrets()
/// let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")
///
/// try await secrets.setAuthToken("abc123")  // saves to keychain
/// let token = try await secrets.authToken    // loads; nil if absent
/// try await secrets.setAuthToken(nil)        // deletes from keychain
/// ```
@attached(accessor)
@attached(peer, names: prefixed(_), arbitrary)
public macro KeychainItem(
    _ account: String,
    service: String? = nil,
    accessGroup: String? = nil,
    accessibility: KeychainAccessibility = .whenUnlocked,
    isSynchronizable: Bool = false,
    label: String? = nil,
    comment: String? = nil
) = #externalMacro(module: "SwiftyChainMacros", type: "KeychainItemMacro")

/// Synthesizes a typed keychain scope, grouping `@KeychainItem` properties under a shared service.
///
/// Apply `@KeychainScope` to a class, struct, or enum; all `@KeychainItem` properties
/// declared within it inherit the `service` (and optional `accessGroup`) automatically,
/// so you don't have to repeat those values on every property.
///
/// The scope also synthesizes a `static func deleteAll()` that bulk-deletes every
/// item stored under the service.
///
/// ```swift
/// @KeychainScope(service: "com.example.app")
/// class AppSecrets {
///     @KeychainItem("auth-token")
///     var authToken: String?
///
///     @KeychainItem("refresh-token")
///     var refreshToken: String?
/// }
///
/// try await AppSecrets.deleteAll()
/// ```
///
/// ## Injecting a keychain for tests
///
/// Pass a `keychain:` expression to replace `Keychain.shared` with any
/// ``KeychainProtocol`` at runtime. The typical pattern uses a lazy static
/// that reads a launch-time environment variable:
///
/// ```swift
/// enum AppDependencies {
///     static let keychain: any KeychainProtocol = {
///         #if DEBUG
///         if ProcessInfo.processInfo.environment["USE_MOCK_KEYCHAIN"] == "1" {
///             return InMemoryKeychain()
///         }
///         #endif
///         return Keychain.shared
///     }()
/// }
///
/// @KeychainScope(service: "com.example.app", keychain: AppDependencies.keychain)
/// class AppSecrets {
///     @KeychainItem("auth-token")
///     var authToken: String?
/// }
/// ```
///
/// In UI tests, set the environment variable before launch:
///
/// ```swift
/// app.launchEnvironment["USE_MOCK_KEYCHAIN"] = "1"
/// app.launch()
/// ```
///
/// See the Testing article for the full pattern, including pre-seeding values.
@attached(member, names: arbitrary)
public macro KeychainScope(
    service: String,
    accessGroup: String? = nil,
    keychain: (any KeychainProtocol)? = nil
) = #externalMacro(module: "SwiftyChainMacros", type: "KeychainScopeMacro")
