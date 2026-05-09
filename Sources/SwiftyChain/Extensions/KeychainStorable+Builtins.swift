import Foundation

extension String: KeychainStorable {
    public func keychainData() throws -> Data {
        guard let data = data(using: .utf8) else {
            throw KeychainError.encodingFailed("Unable to encode string as UTF-8")
        }
        return data
    }

    public static func fromKeychainData(_ data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed("Unable to decode UTF-8 string")
        }
        return value
    }
}

extension Data: KeychainStorable {
    public func keychainData() throws -> Data { self }
    public static func fromKeychainData(_ data: Data) throws -> Data { data }
}

extension Bool: KeychainStorable {
    public func keychainData() throws -> Data {
        Data([self ? 1 : 0])
    }

    public static func fromKeychainData(_ data: Data) throws -> Bool {
        guard data.count == 1, let byte = data.first else {
            throw KeychainError.unexpectedData
        }
        return byte != 0
    }
}

extension Int: KeychainStorable {
    public func keychainData() throws -> Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }

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
    public func keychainData() throws -> Data {
        try bitPattern.keychainData()
    }

    public static func fromKeychainData(_ data: Data) throws -> Double {
        Double(bitPattern: try UInt64.fromKeychainData(data))
    }
}

extension UInt64: KeychainStorable {
    public func keychainData() throws -> Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }

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
