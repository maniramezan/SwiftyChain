import Foundation
import Testing
import SwiftyChain

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
