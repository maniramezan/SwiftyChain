#if os(Linux)
    import Foundation
    import SwiftyChainCore
    import SwiftyChainSecretService
    import Testing

    /// Items in a collection other than the default one. Runs only inside
    /// `scripts/with-gnome-keyring.sh` with `SWIFTYCHAIN_RUN_SECRET_SERVICE_INTEGRATION=1`.
    /// GNOME Keyring always has an unlocked in-memory `session` collection beside the
    /// default `login` one; `secret-tool` (from libsecret-tools) stores an item there.
    @Suite(
        "Secret Service with a second collection",
        .enabled(
            if: ProcessInfo.processInfo.environment["SWIFTYCHAIN_RUN_SECRET_SERVICE_INTEGRATION"] == "1"
                && ProcessInfo.processInfo.environment["SWIFTYCHAIN_KEYRING_SESSION"] == "1"
        )
    )
    struct SecretServiceCollectionTests {
        @Test
        func updatesChangeTheItemInItsOwnCollection() throws {
            let backend = SecretServiceBackend()
            let service = "tests.collection.\(UUID().uuidString)"
            let key = KeychainQuery(itemClass: .genericPassword, service: service, account: "token")
            let read = KeychainQuery(
                itemClass: .genericPassword,
                service: service,
                account: "token",
                returnData: true
            )
            try Self.storeInSessionCollection(service: service, secret: "first")
            defer {
                do {
                    try backend.delete(matching: KeychainQuery(itemClass: .genericPassword, service: service))
                } catch {
                    Issue.record("Could not clean up collection test items: \(error)")
                }
            }
            #expect(try backend.copyMatching(read) == .data(Data("first".utf8)))

            try backend.update(
                matching: key,
                to: KeychainAttributes(data: Data("second".utf8), label: "renamed", comment: nil, accessibility: nil)
            )

            let matches = try SecretServiceClient(timeout: .seconds(30)).search(
                SecretServiceAttributes.matching(key),
                loadSecrets: true
            )
            #expect(matches.count == 1)
            #expect(matches.first?.secret == Data("second".utf8))
            #expect(matches.first?.label == "renamed")
            #expect(try Self.itemPaths(service: service).allSatisfy { $0.contains("/collection/session/") })
        }

        private static func storeInSessionCollection(service: String, secret: String) throws {
            let store = """
                printf %s "$1" | secret-tool store --label=original --collection=session \
                    xdg:schema "$2" service "$3" account token accessGroup ""
                """
            let status = try runCommand([
                "sh", "-c", store, "sh", secret, SecretServiceSchema.genericPassword.name, service,
            ])
            try #require(status == 0)
        }

        /// The D-Bus object paths of every item with this service, which name the
        /// collection holding each item.
        private static func itemPaths(service: String) throws -> [String] {
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftychain-items-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: output) }
            let search = """
                dbus-send --session --print-reply --dest=org.freedesktop.secrets /org/freedesktop/secrets \
                    org.freedesktop.Secret.Service.SearchItems dict:string:string:service,"$1" > "$2"
                """
            try #require(try runCommand(["sh", "-c", search, "sh", service, output.path]) == 0)
            let reply = try String(contentsOf: output, encoding: .utf8)
            let paths = reply.split(separator: "\"").map(String.init).filter {
                $0.hasPrefix("/org/freedesktop/secrets/collection/")
            }
            try #require(!paths.isEmpty)
            return paths
        }
    }
#endif
