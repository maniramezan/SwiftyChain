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

#if Observation
    @Test(.timeLimit(.minutes(1)))
    func sharedRegistryReceivesStorageAndOtherActorWrites() async throws {
        let service = "tests.observation.shared.\(UUID().uuidString)"
        let backend = InMemoryKeychainBackend()
        let registry = KeychainObserverRegistry.platformDefault
        let observer = KeychainEngine(backend: backend, observers: registry)
        let writer = KeychainEngine(backend: backend, observers: registry)
        let stream = observer.observeKeychainChanges(service: service, accessGroup: nil)
        let key = KeychainKey<String>(service: service, account: "token")
        try writer.upsert("value", for: key)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == KeychainChangeEvent(service: service, account: "token", kind: .saved))
    }

    @Test(.timeLimit(.minutes(1)))
    func internetEventsNameTheirServer() async throws {
        let keychain = InMemoryKeychain()
        let key = InternetPasswordKey(server: "observation.example.com", account: "alice")
        let stream = await keychain.observeKeychainChanges(server: key.server)
        try await keychain.saveInternetPassword("secret", for: key)
        try await keychain.deleteInternetPassword(for: key)
        var iterator = stream.makeAsyncIterator()
        let saved = await iterator.next()
        let deleted = await iterator.next()
        #expect(saved?.service == nil)
        #expect(saved?.server == key.server)
        #expect(saved?.kind == .saved)
        #expect(deleted?.kind == .deleted)
    }

    #if canImport(Security)
        @Test(
            .enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_KEYCHAIN_INTEGRATION"] == "1"),
            .timeLimit(.minutes(1)))
        func storageAndPlatformInstancesReachSharedObservers() async throws {
            let service = "tests.observation.storage.\(UUID().uuidString)"
            let stream = await Keychain.shared.observeKeychainChanges(service: service)
            let storage = KeychainStorage<String>("token", service: service)
            storage.wrappedValue = "first"
            try #require(storage.projectedValue == nil)
            let key = KeychainKey<String>(service: service, account: "token")
            do {
                try await Keychain().update("second", for: key)
                storage.wrappedValue = nil
                var iterator = stream.makeAsyncIterator()
                #expect(await iterator.next()?.kind == .saved)
                #expect(await iterator.next()?.kind == .updated)
                #expect(await iterator.next()?.kind == .deleted)
            } catch {
                try? await Keychain.shared.delete(key: key)
                throw error
            }
        }
    #endif
#endif

#if Observation
    @Test(.timeLimit(.minutes(1)))
    func customBackendEnginesKeepTheirOwnObservers() async throws {
        let backend = InMemoryKeychainBackend()
        let observer = Keychain(backend: backend)
        let other = Keychain(backend: backend)
        let service = "tests.observation.custom.\(UUID().uuidString)"
        let stream = await observer.observeKeychainChanges(service: service)
        let storage = KeychainStorage<String>("storage", service: service, backend: backend)
        storage.wrappedValue = "value"
        try await other.save("value", for: KeychainKey<String>(service: service, account: "other"))
        try await observer.save("value", for: KeychainKey<String>(service: service, account: "own"))
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next()?.account == "own")
    }
#endif
