import SwiftyChainCore
import SwiftyChainSecretService
import Testing

#if os(Linux)
    import CSwiftyChainSecret
#endif

@Suite("Secret Service attribute mapping")
struct SecretServiceAttributesTests {
    @Test
    func identityStoresEveryGenericPasswordAttribute() throws {
        let identity = try SecretServiceAttributes.identity(
            for: KeychainQuery(itemClass: .genericPassword, service: "com.example", account: "alice")
        )

        #expect(identity.schema == .genericPassword)
        #expect(identity.attributes == ["service": "com.example", "account": "alice", "accessGroup": ""])
    }

    @Test
    func identityStoresEveryInternetPasswordAttribute() throws {
        let identity = try SecretServiceAttributes.identity(
            for: KeychainQuery(
                itemClass: .internetPassword,
                account: "alice",
                accessGroup: "group.a",
                server: "example.com",
                internetProtocol: .https,
                authenticationType: .htmlForm
            )
        )

        #expect(identity.schema == .internetPassword)
        #expect(
            identity.attributes == [
                "server": "example.com",
                "account": "alice",
                "port": "0",
                "path": "",
                "protocol": "https",
                "authenticationType": "html-form",
                "accessGroup": "group.a",
            ]
        )
    }

    @Test
    func matchingOmitsUnsetAttributesSoTheyMatchAnything() throws {
        let matching = try SecretServiceAttributes.matching(
            KeychainQuery(itemClass: .genericPassword, service: "com.example", isSynchronizable: false)
        )

        #expect(matching.attributes == ["service": "com.example"])
    }

    @Test
    func matchingKeepsExplicitInternetAttributes() throws {
        let matching = try SecretServiceAttributes.matching(
            KeychainQuery(itemClass: .internetPassword, account: "alice", server: "example.com", port: 8443)
        )

        #expect(matching.attributes == ["server": "example.com", "account": "alice", "port": "8443"])
    }

    @Test
    func labelsDefaultToServiceAndAccount() throws {
        let generic = KeychainQuery(itemClass: .genericPassword, service: "com.example", account: "alice")
        let internet = KeychainQuery(itemClass: .internetPassword, account: "alice", server: "example.com")
        let custom = KeychainQuery(itemClass: .genericPassword, service: "s", account: "a", label: "My token")

        #expect(try SecretServiceAttributes.label(for: generic) == "com.example (alice)")
        #expect(try SecretServiceAttributes.label(for: internet) == "alice@example.com")
        #expect(try SecretServiceAttributes.label(for: custom) == "My token")
    }

    @Test
    func storedAttributesMapBackToKeychainAttributes() {
        let attributes = SecretServiceAttributes.keychainAttributes(
            from: ["service": "com.example", "account": "alice", "accessGroup": ""]
        )

        #expect(attributes == [.account("alice"), .service("com.example")])
    }

    @Test(
        arguments: [
            KeychainQuery(itemClass: .genericPassword, service: "com.example"),
            KeychainQuery(itemClass: .genericPassword, accessGroup: "group.a"),
            KeychainQuery(itemClass: .genericPassword, service: "", account: "token"),
            KeychainQuery(itemClass: .internetPassword, server: "example.com"),
            KeychainQuery(itemClass: .internetPassword, account: "alice", server: ""),
        ]
    )
    func deletesNamingOneAppsItemsAreScoped(_ query: KeychainQuery) throws {
        #expect(SecretServiceAttributes.isScopedForDeletion(try SecretServiceAttributes.matching(query)))
    }

    @Test(
        arguments: [
            KeychainQuery(itemClass: .genericPassword),
            KeychainQuery(itemClass: .genericPassword, service: ""),
            KeychainQuery(itemClass: .genericPassword, account: "token"),
            KeychainQuery(itemClass: .genericPassword, accessGroup: ""),
            KeychainQuery(itemClass: .genericPassword, server: "example.com"),
            KeychainQuery(itemClass: .internetPassword, service: "com.example"),
            KeychainQuery(itemClass: .internetPassword, account: "alice", port: 443),
        ]
    )
    func deletesThatWouldMatchOtherAppsItemsAreNotScoped(_ query: KeychainQuery) throws {
        #expect(!SecretServiceAttributes.isScopedForDeletion(try SecretServiceAttributes.matching(query)))
    }

    @Test
    func storedEnumValuesAreUnique() {
        let protocols: [InternetProtocol] = [
            .ftp, .ftpAccount, .http, .irc, .nntp, .pop3, .smtp, .socks, .imap, .ldap, .appleTalk, .afp, .telnet,
            .ssh, .ftps, .https, .httpProxy, .httpsProxy, .ftpProxy, .smb, .rtsp, .rtspProxy, .daap, .eppc, .ipp,
            .nntps, .ldaps, .telnetS, .imaps, .ircs, .pop3S,
        ]
        let authenticationTypes: [AuthenticationType] = [
            .ntlm, .msn, .dpa, .rpa, .httpBasic, .httpDigest, .htmlForm, .default,
        ]

        #expect(Set(protocols.map(SecretServiceAttributes.storedValue)).count == protocols.count)
        #expect(Set(authenticationTypes.map(SecretServiceAttributes.storedValue)).count == authenticationTypes.count)
    }

    #if Cryptography
        @Test
        func cryptographicKeysHaveNoSchema() {
            let query = KeychainQuery(itemClass: .cryptographicKey, service: "com.example")
            let unsupported = KeychainError.platformUnsupported(
                "Cryptographic keys are not supported by this keychain backend"
            )

            #expect(throws: unsupported) { try SecretServiceAttributes.schema(for: .cryptographicKey) }
            #expect(throws: unsupported) { try SecretServiceAttributes.matching(query) }
            #expect(throws: unsupported) { try SecretServiceAttributes.identity(for: query) }
        }
    #endif

    #if os(Linux)
        @Test(arguments: [SecretServiceSchema.genericPassword, .internetPassword])
        func swiftAttributeNamesMatchTheCSchema(_ schema: SecretServiceSchema) {
            let kind =
                schema == .genericPassword ? SWIFTYCHAIN_SECRET_GENERIC_PASSWORD : SWIFTYCHAIN_SECRET_INTERNET_PASSWORD
            var names: [String] = []
            var index: Int32 = 0
            while let name = swiftychain_secret_schema_attribute_name(kind, index) {
                names.append(String(cString: name))
                index += 1
            }

            #expect(names == schema.attributeNames)
            #expect(swiftychain_secret_schema_name(kind).map { String(cString: $0) } == schema.name)
        }
    #endif
}
