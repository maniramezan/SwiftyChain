import Foundation
import Testing

@testable import SwiftyChain

@Test
func keychainStorageRoundTripsViaPropertyWrapper() throws {
    let backend = MockKeychainBackend()
    let storage = KeychainStorage<String>("token", service: "tests", backend: backend)

    #expect(storage.wrappedValue == nil)

    storage.wrappedValue = "abc"
    #expect(storage.wrappedValue == "abc")
    #expect(storage.projectedValue == nil)

    storage.wrappedValue = "xyz"
    #expect(storage.wrappedValue == "xyz")

    storage.wrappedValue = nil
    #expect(storage.wrappedValue == nil)
}

@Test
func keychainStorageReportsErrorsOnProjectedValue() throws {
    let backend = FailingBackend()
    let storage = KeychainStorage<String>("token", service: "tests", backend: backend)

    storage.wrappedValue = "anything"
    #expect(storage.projectedValue == .operationFailed(-1))
}

@Test
func keychainStorageReturnsDefaultWhenMissing() throws {
    let backend = MockKeychainBackend()
    let storage = KeychainStorage<String>(
        "missing",
        service: "tests",
        backend: backend,
        defaultValue: "fallback"
    )

    #expect(storage.wrappedValue == "fallback")
    #expect(storage.projectedValue == nil)
}

@Test
func keychainStorageWorksOnLetValue() throws {
    let backend = MockKeychainBackend()
    let storage = KeychainStorage<String>("token", service: "tests", backend: backend)
    storage.wrappedValue = "stored"
    #expect(storage.wrappedValue == "stored")
}

private struct FailingBackend: SecureStorageBackend {
    func add(_ query: KeychainQuery, data: Data) throws {
        throw KeychainError.operationFailed(-1)
    }

    func copyMatching(_ query: KeychainQuery) throws -> KeychainQueryResult {
        throw KeychainError.operationFailed(-1)
    }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        throw KeychainError.operationFailed(-1)
    }

    func delete(matching query: KeychainQuery) throws {
        throw KeychainError.operationFailed(-1)
    }
}
