import Foundation
import Testing

@testable import SwiftyChain

private struct DummyError: Error, CustomStringConvertible {
    let description: String
}

@Test
func encodingFailedFromErrorEmbedsDescription() throws {
    let underlying = DummyError(description: "encoder blew up")
    let error: KeychainError = .encodingFailed(String(describing: underlying))

    guard case .encodingFailed(let message) = error else {
        Issue.record("expected encodingFailed")
        return
    }
    #expect(message.contains("encoder blew up"))
}

@Test
func decodingFailedFromErrorEmbedsDescription() throws {
    let underlying = DummyError(description: "bad bytes")
    let error: KeychainError = .decodingFailed(String(describing: underlying))

    guard case .decodingFailed(let message) = error else {
        Issue.record("expected decodingFailed")
        return
    }
    #expect(message.contains("bad bytes"))
}

@Test
func keychainErrorsAreEquatable() {
    #expect(KeychainError.itemNotFound == KeychainError.itemNotFound)
    #expect(KeychainError.operationFailed(-1) != KeychainError.operationFailed(-2))
    #expect(KeychainError.encodingFailed("a") != KeychainError.encodingFailed("b"))
}

@Test
func derivedEncodingAndDecodingErrorsCaptureDescriptions() {
    let encodingError = KeychainError.encodingFailed(DummyError(description: "encode-failure") as any Error)
    let decodingError = KeychainError.decodingFailed(DummyError(description: "decode-failure") as any Error)

    #expect(encodingError == .encodingFailed("encode-failure"))
    #expect(decodingError == .decodingFailed("decode-failure"))
}

@Test
func keychainErrorLogNamesCoverAllCases() {
    let cases: [(KeychainError, String)] = [
        (.itemNotFound, "itemNotFound"),
        (.duplicateItem, "duplicateItem"),
        (.authenticationFailed, "authenticationFailed"),
        (.userPresenceRequired, "userPresenceRequired"),
        (.unexpectedData, "unexpectedData"),
        (.encodingFailed("x"), "encodingFailed"),
        (.decodingFailed("x"), "decodingFailed"),
        (.operationFailed(-1), "operationFailed"),
        (.accessGroupDenied, "accessGroupDenied"),
        (.platformUnsupported("nope"), "platformUnsupported"),
    ]

    for (error, expectedLogName) in cases {
        #expect(error.logName == expectedLogName)
    }
}
