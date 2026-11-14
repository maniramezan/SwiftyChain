import Foundation
import SwiftyChain
import SwiftyChainTesting
import Testing

@Test
func keychainStorageRoundTripsViaPropertyWrapper() throws {
    let backend = InMemoryKeychainBackend()
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
func keychainStorageWorksOnLetValue() throws {
    let backend = InMemoryKeychainBackend()
    let storage = KeychainStorage<String>("token", service: "tests", backend: backend)
    storage.wrappedValue = "stored"
    #expect(storage.wrappedValue == "stored")
}

@Test
func keychainStorageUsesUpdateAfterDuplicateSave() throws {
    let backend = DuplicateThenUpdateBackend()
    let storage = KeychainStorage<String>("token", service: "tests", backend: backend)

    storage.wrappedValue = "updated"

    #expect(backend.updatedData == Data("updated".utf8))
    #expect(storage.projectedValue == nil)
}

@Test
func keychainStorageMapsUnexpectedReadErrorsToUnexpectedData() throws {
    let storage = KeychainStorage<String>("token", service: "tests", backend: ThrowingUnexpectedErrorBackend())

    #expect(storage.wrappedValue == nil)
    #expect(storage.projectedValue == .unexpectedData)
}

@Test
func keychainStorageMapsUnexpectedWriteErrorsToUnexpectedData() throws {
    let storage = KeychainStorage<String>("token", service: "tests", backend: ThrowingUnexpectedErrorBackend())

    storage.wrappedValue = "value"

    #expect(storage.projectedValue == .unexpectedData)
}

@Test
func keychainStorageClearsProjectedErrorAfterSuccessfulRead() throws {
    let backend = RecoveringLoadBackend()
    let storage = KeychainStorage<String>("token", service: "tests", backend: backend)

    #expect(storage.wrappedValue == nil)
    #expect(storage.projectedValue == .operationFailed(-1))

    backend.mode = .success(Data("restored".utf8))

    #expect(storage.wrappedValue == "restored")
    #expect(storage.projectedValue == nil)
}

/// A backend whose every call fails with the same error.
private struct FailingBackend: KeychainBackend {
    var error: any Error = KeychainError.operationFailed(-1)
    let capabilities: KeychainBackendCapabilities = .all

    func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws { throw error }
    func data(matching query: KeychainQuery) throws -> Data { throw error }
    func contains(matching query: KeychainQuery) throws -> Bool { throw error }
    func accounts(matching query: KeychainQuery) throws -> [String] { throw error }
    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws { throw error }
    func delete(matching query: KeychainQuery) throws { throw error }
}

private final class DuplicateThenUpdateBackend: KeychainBackend, @unchecked Sendable {
    let capabilities: KeychainBackendCapabilities = .all
    var updatedData: Data?

    func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {
        throw KeychainError.duplicateItem
    }

    func data(matching query: KeychainQuery) throws -> Data { throw KeychainError.itemNotFound }
    func contains(matching query: KeychainQuery) throws -> Bool { true }
    func accounts(matching query: KeychainQuery) throws -> [String] { [] }

    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {
        updatedData = attributes.data
    }

    func delete(matching query: KeychainQuery) throws {}
}

private struct ThrowingUnexpectedErrorBackend: KeychainBackend {
    struct Boom: Error {}

    let capabilities: KeychainBackendCapabilities = .all

    func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws { throw Boom() }
    func data(matching query: KeychainQuery) throws -> Data { throw Boom() }
    func contains(matching query: KeychainQuery) throws -> Bool { throw Boom() }
    func accounts(matching query: KeychainQuery) throws -> [String] { throw Boom() }
    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws { throw Boom() }
    func delete(matching query: KeychainQuery) throws { throw Boom() }
}

private final class RecoveringLoadBackend: KeychainBackend, @unchecked Sendable {
    enum Mode {
        case failure
        case success(Data)
    }

    let capabilities: KeychainBackendCapabilities = .all
    var mode: Mode = .failure

    func add(_ query: KeychainQuery, attributes: KeychainAttributes) throws {}

    func data(matching query: KeychainQuery) throws -> Data {
        switch mode {
        case .failure:
            throw KeychainError.operationFailed(-1)
        case .success(let data):
            return data
        }
    }

    func contains(matching query: KeychainQuery) throws -> Bool { true }
    func accounts(matching query: KeychainQuery) throws -> [String] { [] }
    func update(matching query: KeychainQuery, to attributes: KeychainAttributes) throws {}
    func delete(matching query: KeychainQuery) throws {}
}
