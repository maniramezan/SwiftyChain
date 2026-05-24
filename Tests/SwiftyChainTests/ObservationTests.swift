#if Observation
    import Foundation
    import Testing
    import SwiftyChain
    import SwiftyChainTesting

    @Test
    func observerReceivesSaveUpdateAndDeleteEvents() async throws {
        let keychain = InMemoryKeychain()
        let key = KeychainKey<String>(service: "tests.observation", account: "token")
        let stream = await keychain.observeKeychainChanges(service: "tests.observation")

        try await keychain.save("v1", for: key)
        try await keychain.update("v2", for: key)
        try await keychain.delete(key: key)

        var collected: [KeychainChangeEvent.Kind] = []
        var iterator = stream.makeAsyncIterator()
        for _ in 0..<3 {
            guard let event = await iterator.next() else { break }
            collected.append(event.kind)
        }

        #expect(collected == [.saved, .updated, .deleted])
    }

    @Test
    func observerIsScopedToService() async throws {
        let keychain = InMemoryKeychain()
        let stream = await keychain.observeKeychainChanges(service: "tests.observation.scoped")

        try await keychain.save(
            "v",
            for: KeychainKey<String>(service: "tests.observation.scoped", account: "a")
        )
        try await keychain.save(
            "v",
            for: KeychainKey<String>(service: "other.service", account: "a")
        )

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.service == "tests.observation.scoped")
    }

    @Test
    func bulkDeleteEmitsBulkDeletedEvent() async throws {
        let keychain = InMemoryKeychain()
        let stream = await keychain.observeKeychainChanges(service: "tests.observation.bulk")

        try await keychain.deleteAll(service: "tests.observation.bulk")

        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event?.kind == .bulkDeleted)
    }
#endif
