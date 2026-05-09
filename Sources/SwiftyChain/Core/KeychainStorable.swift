import Foundation

/// A value that can be serialized into keychain data and reconstructed from it.
public protocol KeychainStorable: Sendable {
    func keychainData() throws -> Data
    static func fromKeychainData(_ data: Data) throws -> Self
}

/// Wrapper for storing arbitrary `Codable & Sendable` values using binary property lists.
public struct CodableKeychainStorable<Value: Codable & Sendable>: KeychainStorable, Sendable {
    public let value: Value

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
