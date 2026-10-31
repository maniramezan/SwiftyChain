import Foundation

/// A value that can be serialized into keychain `Data` and reconstructed from it.
///
/// Conform your own types to ``KeychainStorable`` to store them directly in the keychain.
/// For `Codable` types the built-in ``CodableKeychainStorable`` wrapper is often simpler.
///
/// ## Built-in conformances
///
/// SwiftyChain ships conformances for `String`, `Data`, `Bool`, `Int`, `Double`, and `UInt64`.
///
/// ## Custom conformance example
///
/// ```swift
/// struct AuthToken: KeychainStorable {
///     let value: String
///
///     func keychainData() throws -> Data {
///         try value.keychainData()
///     }
///
///     static func fromKeychainData(_ data: Data) throws -> AuthToken {
///         AuthToken(value: try String.fromKeychainData(data))
///     }
/// }
/// ```
public protocol KeychainStorable: Sendable {
    /// Serializes this value into raw `Data` for storage in the keychain.
    ///
    /// - Returns: The binary representation of the value.
    /// - Throws: ``KeychainError/encodingFailed(_:)`` if serialization fails.
    func keychainData() throws -> Data

    /// Reconstructs a value from raw keychain `Data`.
    ///
    /// - Parameter data: The raw `Data` retrieved from the keychain.
    /// - Returns: The decoded value.
    /// - Throws: ``KeychainError/decodingFailed(_:)`` if deserialization fails.
    static func fromKeychainData(_ data: Data) throws -> Self
}

/// Wrapper for storing arbitrary `Codable & Sendable` values using binary property lists.
///
/// Use this type when you want to store a `Codable` type without writing a custom
/// ``KeychainStorable`` conformance. Values are encoded with `PropertyListEncoder`
/// in binary format for compact storage.
///
/// ```swift
/// struct UserPreferences: Codable, Sendable {
///     var theme: String
///     var fontSize: Int
/// }
///
/// let key = KeychainKey<CodableKeychainStorable<UserPreferences>>(
///     service: "com.example.app",
///     account: "preferences"
/// )
/// let prefs = CodableKeychainStorable(UserPreferences(theme: "dark", fontSize: 14))
/// try await Keychain.shared.upsert(prefs, for: key)
/// ```
public struct CodableKeychainStorable<Value: Codable & Sendable>: KeychainStorable, Sendable {
    /// The wrapped `Codable` value.
    public let value: Value

    /// Wraps a `Codable` value for keychain storage.
    ///
    /// - Parameter value: The value to wrap.
    public init(_ value: Value) {
        self.value = value
    }

    public func keychainData() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        do {
            return try encoder.encode(value)
        } catch {
            throw KeychainError.encodingFailed(error)
        }
    }

    public static func fromKeychainData(_ data: Data) throws -> Self {
        do {
            return try Self(PropertyListDecoder().decode(Value.self, from: data))
        } catch {
            throw KeychainError.decodingFailed(error)
        }
    }
}

extension CodableKeychainStorable: Equatable where Value: Equatable {}
