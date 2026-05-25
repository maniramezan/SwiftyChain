import Testing

@testable import SwiftyChain

// These type definitions are compile-time tests for macro correctness.
// If the generated code is invalid Swift (e.g. `nil` without a type context,
// or `Self()` on a class), this file fails to compile and the test target
// won't build — catching bugs that assertMacroExpansion string-comparison misses.

@KeychainScope(service: "dev.test.compile")
private struct ScopeWithoutAccessGroup {
    @KeychainItem("item")
    var item: String?
}

@KeychainScope(service: "dev.test.compile", accessGroup: "group.test")
private struct ScopeWithAccessGroup {
    @KeychainItem("item")
    var item: String?
}

@KeychainScope(service: "dev.test.compile")
private final class ClassScope {
    @KeychainItem("item")
    var item: String?
}

// A struct with stored properties alongside @KeychainItem: if `shared = Self()`
// were still generated the synthesised empty init would break for non-defaulted
// stored properties, causing a compile error here.
@KeychainScope(service: "dev.test.compile")
private struct ScopeWithStoredProperty {
    let tag: String
    @KeychainItem("item")
    var item: String?
}

@Test
func keychainScopeDeleteAllIsStatic() async throws {
    // Verify deleteAll() is callable as a static method (no instance needed).
    // Actual keychain access is skipped; we only confirm the call compiles.
    _ = ScopeWithoutAccessGroup.deleteAll
    _ = ScopeWithAccessGroup.deleteAll
    _ = ClassScope.deleteAll
}
