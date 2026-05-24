import Foundation
import Testing
import SwiftyChain
import SwiftyChainTesting

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
func keychainStorageReturnsDefaultWhenMissing() throws {
    let backend = InMemoryKeychainBackend()
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
    let backend = InMemoryKeychainBackend()
    let storage = KeychainStorage<String>("token", service: "tests", backend: backend)
    storage.wrappedValue = "stored"
    #expect(storage.wrappedValue == "stored")
}

private struct FailingBackend: KeychainBackend {
    func save(
        _ data: Data,
        service: String,
        account: String,
        accessGroup: String?,
        accessibility: KeychainAccessibility,
        isSynchronizable: Bool,
        label: String?,
        comment: String?
    ) throws {
        throw KeychainError.operationFailed(-1)
    }

    func load(service: String, account: String, accessGroup: String?, isSynchronizable: Bool) throws -> Data {
        throw KeychainError.operationFailed(-1)
    }

    func update(
        _ data: Data,
        service: String,
        account: String,
        accessGroup: String?,
        accessibility: KeychainAccessibility,
        isSynchronizable: Bool,
        label: String?,
        comment: String?
    ) throws {
        throw KeychainError.operationFailed(-1)
    }

    func delete(service: String, account: String, accessGroup: String?, isSynchronizable: Bool) throws {
        throw KeychainError.operationFailed(-1)
    }
}
