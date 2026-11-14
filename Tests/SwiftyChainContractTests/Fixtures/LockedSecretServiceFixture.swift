#if os(Linux)
    import Foundation
    import SwiftyChain
    import SwiftyChainSecretService
    import Testing

    struct LockedSecretServiceFixture {
        let backend = SecretServiceBackend(timeout: .seconds(2))
        let key = KeychainKey<String>(service: "tests.locked.\(UUID().uuidString)", account: "token")

        private var query: KeychainQuery {
            KeychainQuery(service: key.service, account: key.account)
        }

        func storeAndLock() throws {
            try backend.add(query, data: Data("secret".utf8))
            let collection = try collectionPath()
            _ = try dbusCall(
                path: "/org/freedesktop/secrets",
                arguments: ["org.freedesktop.Secret.Service.Lock", "array:objpath:\(collection)"]
            )
            try #require(try isLocked(collection: collection))
        }

        func unlock() throws {
            let script = """
                import dbus
                import os

                bus = dbus.SessionBus()
                proxy = bus.get_object("org.freedesktop.secrets", "/org/freedesktop/secrets")
                service = dbus.Interface(proxy, "org.freedesktop.Secret.Service")
                _, session = service.OpenSession("plain", dbus.String("", variant_level=1))
                password = os.environ.get("SWIFTYCHAIN_KEYRING_PASSWORD", "swiftychain").encode()
                master = (session, dbus.ByteArray(b""), dbus.ByteArray(password), "text/plain")
                internal = dbus.Interface(proxy, "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface")
                internal.UnlockWithMasterPassword(service.ReadAlias("default"), master)
                """
            _ = try run("/usr/bin/python3", arguments: ["-c", script])
            try #require(try isLocked(collection: collectionPath()) == false)
        }

        func cleanUp() {
            do {
                try unlock()
                try backend.delete(matching: query)
            } catch {
                Issue.record(error)
            }
        }

        private func collectionPath() throws -> String {
            let response = try dbusCall(
                path: "/org/freedesktop/secrets",
                arguments: ["org.freedesktop.Secret.Service.ReadAlias", "string:default"]
            )
            return String(try #require(response.split(separator: "\"").dropFirst().first))
        }

        private func isLocked(collection: String) throws -> Bool {
            let response = try dbusCall(
                path: collection,
                arguments: [
                    "org.freedesktop.DBus.Properties.Get",
                    "string:org.freedesktop.Secret.Collection",
                    "string:Locked",
                ]
            )
            return response.contains("boolean true")
        }

        private func dbusCall(path: String, arguments: [String]) throws -> String {
            try run(
                "/usr/bin/dbus-send",
                arguments: ["--session", "--print-reply", "--dest=org.freedesktop.secrets", path] + arguments
            )
        }

        private func run(_ executable: String, arguments: [String]) throws -> String {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let response = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            try #require(process.terminationStatus == 0, "\(executable): \(response)")
            return response
        }
    }
#endif
