import Foundation
import Testing

@testable import SwiftyChain

private struct Credentials: Codable, Sendable, Equatable {
    let username: String
    let password: String
}

@Test
func codableKeychainStorableRoundTrips() async throws {
    let keychain = Keychain(backend: MockKeychainBackend())
    let key = KeychainKey<CodableKeychainStorable<Credentials>>(
        service: "tests",
        account: "credentials"
    )

    let creds = CodableKeychainStorable(Credentials(username: "alice", password: "s3cret"))
    try await keychain.save(creds, for: key)

    let loaded = try await keychain.load(key: key)
    #expect(loaded.value == creds.value)
}

@Test
func codableKeychainStorableSurfacesDecodingFailure() throws {
    let bogus = Data("not a plist".utf8)
    #expect(throws: KeychainError.self) {
        _ = try CodableKeychainStorable<Credentials>.fromKeychainData(bogus)
    }
}
