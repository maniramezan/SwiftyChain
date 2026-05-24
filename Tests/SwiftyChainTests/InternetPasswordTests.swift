import Foundation
import SwiftyChain
import SwiftyChainTesting
import Testing

@Test
func internetPasswordRoundTrips() async throws {
    let keychain = InMemoryKeychain()
    let key = InternetPasswordKey(
        server: "example.com",
        account: "alice",
        protocol: .https,
        authenticationType: .httpBasic
    )

    try await keychain.saveInternetPassword("hunter2", for: key)
    #expect(try await keychain.loadInternetPassword(for: key) == "hunter2")

    try await keychain.deleteInternetPassword(for: key)
    await #expect(throws: KeychainError.itemNotFound) {
        try await keychain.loadInternetPassword(for: key)
    }
}

@Test
func internetPasswordsDistinguishedByProtocol() async throws {
    let keychain = InMemoryKeychain()
    let httpsKey = InternetPasswordKey(
        server: "example.com",
        account: "alice",
        protocol: .https
    )
    let httpKey = InternetPasswordKey(
        server: "example.com",
        account: "alice",
        protocol: .http
    )

    try await keychain.saveInternetPassword("secure", for: httpsKey)
    try await keychain.saveInternetPassword("insecure", for: httpKey)

    #expect(try await keychain.loadInternetPassword(for: httpsKey) == "secure")
    #expect(try await keychain.loadInternetPassword(for: httpKey) == "insecure")
}

@Test
func internetPasswordsDistinguishedByPortAndPath() async throws {
    let keychain = InMemoryKeychain()
    let key8080 = InternetPasswordKey(
        server: "example.com",
        account: "alice",
        port: 8080,
        protocol: .http
    )
    let pathKey = InternetPasswordKey(
        server: "example.com",
        account: "alice",
        path: "/admin",
        protocol: .https
    )

    try await keychain.saveInternetPassword("port", for: key8080)
    try await keychain.saveInternetPassword("path", for: pathKey)

    #expect(try await keychain.loadInternetPassword(for: key8080) == "port")
    #expect(try await keychain.loadInternetPassword(for: pathKey) == "path")
}
