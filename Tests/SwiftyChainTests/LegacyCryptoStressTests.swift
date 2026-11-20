#if Cryptography && os(macOS)
    import Foundation
    import Security
    import Testing

    @testable import SwiftyChain

    /// Adds keys to the macOS legacy store while other `Keychain` instances write to it.
    /// Opt in with `SWIFTYCHAIN_RUN_KEYCHAIN_STRESS=1`; `SWIFTYCHAIN_STRESS_MODE` selects the
    /// concurrent traffic, such as `none`, `passwords`, `keys`, or `foreign`.
    @Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_KEYCHAIN_STRESS"] == "1"))
    struct LegacyCryptoStressTests {
        private static let environment = ProcessInfo.processInfo.environment
        private static let iterations = Int(environment["SWIFTYCHAIN_STRESS_ITERATIONS"] ?? "") ?? 100
        private static let workers = Int(environment["SWIFTYCHAIN_STRESS_WORKERS"] ?? "") ?? 4
        private static let mode = environment["SWIFTYCHAIN_STRESS_MODE"] ?? "passwords"

        @Test
        func cryptoKeyAddsSurviveConcurrentTraffic() async throws {
            let service = "tests.stress.\(UUID().uuidString)"
            let mode = Self.mode
            let traffic = Task {
                await withTaskGroup(of: Void.self) { group in
                    guard mode != "none" else { return }
                    for worker in 0..<Self.workers {
                        group.addTask {
                            let keychain = Keychain()
                            var round = 0
                            while !Task.isCancelled {
                                if mode == "keys" {
                                    await Self.addAndDeleteKey(on: keychain)
                                } else {
                                    let key = KeychainKey<String>(service: service, account: "w\(worker)-\(round % 8)")
                                    switch mode {
                                    case "reads":
                                        _ = try? await keychain.loadIfPresent(key: key)
                                    case "updates":
                                        try? await keychain.upsert("value-\(round)", for: key)
                                    case "deletes":
                                        try? await keychain.delete(key: key)
                                    case "foreign":
                                        Self.writeOutsideSwiftyChain(
                                            service: service, account: key.account, round: round)
                                    default:
                                        try? await keychain.upsert("value", for: key)
                                        try? await keychain.delete(key: key)
                                    }
                                }
                                round += 1
                            }
                        }
                    }
                }
            }

            let keychain = Keychain()
            var failures: [String] = []
            for iteration in 0..<Self.iterations {
                if let failure = await Self.addAndDeleteKey(on: keychain) {
                    failures.append("iteration \(iteration): \(failure)")
                }
            }
            traffic.cancel()
            await traffic.value
            try? await keychain.deleteAll(service: service)

            print("STRESS mode=\(mode) iterations=\(Self.iterations) failures=\(failures.count)")
            for failure in failures.prefix(10) { print("STRESS \(failure)") }
            #expect(failures.isEmpty)
        }

        /// Adds a fresh key, loads it back, and deletes it. Returns a description of the
        /// first step that failed, or `nil`.
        @discardableResult
        private static func addAndDeleteKey(on keychain: Keychain) async -> String? {
            let ref = CryptoKeyReference<StoredSecKey>(tag: "tests.stress.crypto.\(UUID().uuidString)")
            let attributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String: 256,
            ]
            guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
                return "key generation failed"
            }
            var failure: String?
            do {
                try await keychain.saveCryptoKey(StoredSecKey(key), for: ref)
                do {
                    _ = try await keychain.loadCryptoKey(keyRef: ref)
                } catch {
                    failure = "load failed: \(error)"
                }
            } catch {
                failure = "save failed: \(error); orphan left behind: \(removeOrphan(of: key))"
            }
            try? await keychain.deleteCryptoKey(keyRef: ref)
            return failure
        }

        /// Writes a password with the Security framework directly, as another library in the
        /// same process would, so the write bypasses SwiftyChain's legacy-store gate.
        private static func writeOutsideSwiftyChain(service: String, account: String, round: Int) {
            let match: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let data = Data("value-\(round)".utf8)
            let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                SecItemAdd(match.merging([kSecValueData as String: data]) { _, new in new } as CFDictionary, nil)
            }
        }

        /// Deletes any stored key with `key`'s public-key hash, which a failed add can leave
        /// without its tag. Returns whether one was found.
        private static func removeOrphan(of key: SecKey) -> Bool {
            let attributes = SecKeyCopyAttributes(key) as? [String: Any] ?? [:]
            guard let label = attributes[kSecAttrApplicationLabel as String] else { return false }
            let query: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationLabel as String: label,
            ]
            return SecItemDelete(query as CFDictionary) == errSecSuccess
        }
    }
#endif
