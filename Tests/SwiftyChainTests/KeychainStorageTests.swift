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
func keychainStorageReturnsDefaultWhenMissing() throws {
    let backend = InMemoryKeychainBackend()
    let storage = DefaultedKeychainStorage<String>(
        "missing",
        service: "tests",
        backend: backend,
        defaultValue: "fallback"
    )

    #expect(storage.wrappedValue == "fallback")
    #expect(storage.projectedValue == nil)
}

@Test
func defaultedKeychainStorageRoundTripsViaPropertyWrapper() throws {
    let backend = InMemoryKeychainBackend()
    let storage = DefaultedKeychainStorage<String>(
        "token",
        service: "tests",
        backend: backend,
        defaultValue: "fallback"
    )

    #expect(storage.wrappedValue == "fallback")

    storage.wrappedValue = "abc"
    #expect(storage.wrappedValue == "abc")
    #expect(storage.projectedValue == nil)
}

@Test
func defaultedKeychainStorageReportsErrorsOnProjectedValue() throws {
    let backend = FailingBackend()
    let storage = DefaultedKeychainStorage<String>(
        "token",
        service: "tests",
        backend: backend,
        defaultValue: "fallback"
    )

    #expect(storage.wrappedValue == "fallback")

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

@Test
func defaultedKeychainStorageReturnsFallbackForUnexpectedReadError() throws {
    let storage = DefaultedKeychainStorage<String>(
        "token",
        service: "tests",
        backend: ThrowingUnexpectedErrorBackend(),
        defaultValue: "fallback"
    )

    #expect(storage.wrappedValue == "fallback")
    #expect(storage.projectedValue == .unexpectedData)
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

private final class DuplicateThenUpdateBackend: KeychainBackend, @unchecked Sendable {
    var updatedData: Data?

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
        throw KeychainError.duplicateItem
    }

    func load(service: String, account: String, accessGroup: String?, isSynchronizable: Bool) throws -> Data {
        throw KeychainError.itemNotFound
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
        updatedData = data
    }

    func delete(service: String, account: String, accessGroup: String?, isSynchronizable: Bool) throws {}
}

private struct ThrowingUnexpectedErrorBackend: KeychainBackend {
    struct Boom: Error {}

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
        throw Boom()
    }

    func load(service: String, account: String, accessGroup: String?, isSynchronizable: Bool) throws -> Data {
        throw Boom()
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
        throw Boom()
    }

    func delete(service: String, account: String, accessGroup: String?, isSynchronizable: Bool) throws {
        throw Boom()
    }
}

private final class RecoveringLoadBackend: KeychainBackend, @unchecked Sendable {
    enum Mode {
        case failure
        case success(Data)
    }

    var mode: Mode = .failure

    func save(
        _ data: Data,
        service: String,
        account: String,
        accessGroup: String?,
        accessibility: KeychainAccessibility,
        isSynchronizable: Bool,
        label: String?,
        comment: String?
    ) throws {}

    func load(service: String, account: String, accessGroup: String?, isSynchronizable: Bool) throws -> Data {
        switch mode {
        case .failure:
            throw KeychainError.operationFailed(-1)
        case .success(let data):
            return data
        }
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
    ) throws {}

    func delete(service: String, account: String, accessGroup: String?, isSynchronizable: Bool) throws {}
}
