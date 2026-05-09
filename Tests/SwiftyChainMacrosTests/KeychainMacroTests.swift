import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import SwiftyChainMacros

let testMacros: [String: Macro.Type] = [
    "keychainKey": KeychainKeyMacro.self,
    "KeychainItem": KeychainItemMacro.self,
    "KeychainScope": KeychainScopeMacro.self,
]

@Test
func keychainKeyMacroExpands() {
    assertMacroExpansion(
        """
        let key: KeychainKey<String> = #keychainKey(service: "app", account: "token")
        """,
        expandedSource: """
            let key: KeychainKey<String> = KeychainKey(
                service: "app",
                account: "token",
                accessGroup: nil,
                accessibility: .whenUnlocked,
                isSynchronizable: false,
                label: nil,
                comment: nil
            )
            """,
        macros: testMacros
    )
}

@Test
func keychainKeyMacroDiagnosesInvalidSynchronizableAccessibility() {
    assertMacroExpansion(
        """
        let key: KeychainKey<String> = #keychainKey(
            service: "app",
            account: "token",
            accessibility: .whenUnlockedThisDeviceOnly,
            isSynchronizable: true
        )
        """,
        expandedSource: """
            let key: KeychainKey<String> = KeychainKey(
                service: "app",
                account: "token",
                accessGroup: nil,
                accessibility: .whenUnlockedThisDeviceOnly,
                isSynchronizable: true,
                label: nil,
                comment: nil
            )
            """,
        diagnostics: [
            DiagnosticSpec(
                message: "'ThisDeviceOnly' accessibility and isSynchronizable: true are mutually exclusive",
                line: 1,
                column: 32
            )
        ],
        macros: testMacros
    )
}

@Test
func keychainItemMacroExpandsOptionalProperty() {
    assertMacroExpansion(
        """
        struct AuthStore {
            @KeychainItem(service: "app", account: "token")
            var authToken: String?
        }
        """,
        expandedSource: """
            struct AuthStore {
                var authToken: String? {
                    get async throws {
                        try await Keychain.shared.loadIfPresent(key: Self._authTokenKey)
                    }
                }

                fileprivate static let _authTokenKey = KeychainKey<String>(
                    service: "app",
                    account: "token",
                    accessGroup: nil,
                    accessibility: .whenUnlocked,
                    isSynchronizable: false,
                    label: nil,
                    comment: nil
                )

                func setAuthToken(_ newValue: String?) async throws {
                    if let newValue {
                        try await Keychain.shared.upsert(newValue, for: Self._authTokenKey)
                    } else {
                        try await Keychain.shared.delete(key: Self._authTokenKey)
                    }
                }
            }
            """,
        macros: testMacros
    )
}

@Test
func keychainItemMacroExpandsRequiredProperty() {
    assertMacroExpansion(
        """
        struct AuthStore {
            @KeychainItem(service: "app", account: "device")
            var deviceID: String
        }
        """,
        expandedSource: """
            struct AuthStore {
                var deviceID: String {
                    get async throws {
                        try await Keychain.shared.load(key: Self._deviceIDKey)
                    }
                }

                fileprivate static let _deviceIDKey = KeychainKey<String>(
                    service: "app",
                    account: "device",
                    accessGroup: nil,
                    accessibility: .whenUnlocked,
                    isSynchronizable: false,
                    label: nil,
                    comment: nil
                )

                func setDeviceID(_ newValue: String) async throws {
                    try await Keychain.shared.upsert(newValue, for: Self._deviceIDKey)
                }
            }
            """,
        macros: testMacros
    )
}

@Test
func keychainScopeMacroExpandsDeleteAll() {
    assertMacroExpansion(
        """
        @KeychainScope(service: "app")
        struct AuthKeys {
        }
        """,
        expandedSource: """
            struct AuthKeys {

                static let shared = Self()

                func deleteAll() async throws {
                    try await Keychain.shared.deleteAll(
                        service: "app",
                        accessGroup: nil
                    )
                }
            }
            """,
        macros: testMacros
    )
}

@Test
func keychainScopeMacroDiagnosesEmptyService() {
    assertMacroExpansion(
        """
        @KeychainScope(service: "")
        struct AuthKeys {
        }
        """,
        expandedSource: """
            struct AuthKeys {
            }
            """,
        diagnostics: [
            DiagnosticSpec(
                message: "service must be a non-empty string literal",
                line: 1,
                column: 1
            )
        ],
        macros: testMacros
    )
}
