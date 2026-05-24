import Foundation

extension String: KeychainStorable {
    /// Encodes the string as UTF-8 data.
    ///
    /// - Throws: ``KeychainError/encodingFailed(_:)`` if UTF-8 encoding fails.
    public func keychainData() throws -> Data {
        guard let data = data(using: .utf8) else {
            throw KeychainError.encodingFailed("Unable to encode string as UTF-8")
        }
        return data
    }

    /// Decodes a UTF-8-encoded string from keychain data.
    ///
    /// - Throws: ``KeychainError/decodingFailed(_:)`` if the data is not valid UTF-8.
    public static func fromKeychainData(_ data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed("Unable to decode UTF-8 string")
        }
        return value
    }
}

extension Data: KeychainStorable {
    /// Returns the data unchanged, since `Data` is already in its serialized form.
    public func keychainData() throws -> Data { self }

    /// Returns the data unchanged.
    public static func fromKeychainData(_ data: Data) throws -> Data { data }
}

extension Bool: KeychainStorable {
    /// Encodes the boolean as a single byte: `1` for `true`, `0` for `false`.
    public func keychainData() throws -> Data {
        Data([self ? 1 : 0])
    }

    /// Decodes a boolean from a single byte.
    ///
    /// - Throws: ``KeychainError/unexpectedData`` if `data` is not exactly one byte.
    public static func fromKeychainData(_ data: Data) throws -> Bool {
        guard data.count == 1, let byte = data.first else {
            throw KeychainError.unexpectedData
        }
        return byte != 0
    }
}

extension Int: KeychainStorable {
    /// Encodes the integer as little-endian bytes.
    public func keychainData() throws -> Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }

    /// Decodes an integer from little-endian bytes.
    ///
    /// - Throws: ``KeychainError/unexpectedData`` if `data` does not match the expected byte length.
    public static func fromKeychainData(_ data: Data) throws -> Int {
        guard data.count == MemoryLayout<Int>.size else {
            throw KeychainError.unexpectedData
        }
        let value = data.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: Int.self)
        }
        return Int(littleEndian: value)
    }
}

extension Double: KeychainStorable {
    /// Encodes the value as its `UInt64` bit pattern in little-endian byte order.
    public func keychainData() throws -> Data {
        try bitPattern.keychainData()
    }

    /// Decodes a `Double` from its `UInt64` bit pattern stored as little-endian bytes.
    public static func fromKeychainData(_ data: Data) throws -> Double {
        Double(bitPattern: try UInt64.fromKeychainData(data))
    }
}

extension UInt64: KeychainStorable {
    /// Encodes the value as little-endian bytes.
    public func keychainData() throws -> Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }

    /// Decodes a `UInt64` from little-endian bytes.
    ///
    /// - Throws: ``KeychainError/unexpectedData`` if `data` is not exactly 8 bytes.
    public static func fromKeychainData(_ data: Data) throws -> UInt64 {
        guard data.count == MemoryLayout<UInt64>.size else {
            throw KeychainError.unexpectedData
        }
        let value = data.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: UInt64.self)
        }
        return UInt64(littleEndian: value)
    }
}
