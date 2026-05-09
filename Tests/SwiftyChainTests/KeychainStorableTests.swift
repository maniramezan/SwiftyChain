import Foundation
import Testing

@testable import SwiftyChain

@Test(arguments: ["", "token", "hello world"])
func stringRoundTrips(value: String) throws {
    #expect(try String.fromKeychainData(value.keychainData()) == value)
}

@Test(arguments: [true, false])
func boolRoundTrips(value: Bool) throws {
    #expect(try Bool.fromKeychainData(value.keychainData()) == value)
}

@Test(arguments: [0, 1, -1, Int.max, Int.min])
func intRoundTrips(value: Int) throws {
    #expect(try Int.fromKeychainData(value.keychainData()) == value)
}

@Test(arguments: [0.0, 1.25, -99.5])
func doubleRoundTrips(value: Double) throws {
    #expect(try Double.fromKeychainData(value.keychainData()) == value)
}

@Test(arguments: [UInt64(0), UInt64(1), UInt64.max])
func uint64RoundTrips(value: UInt64) throws {
    #expect(try UInt64.fromKeychainData(value.keychainData()) == value)
}

@Test(arguments: [Data(), Data([0x00]), Data([0xDE, 0xAD, 0xBE, 0xEF])])
func dataRoundTrips(value: Data) throws {
    #expect(try Data.fromKeychainData(value.keychainData()) == value)
}
