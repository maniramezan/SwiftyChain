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

// The documented scope types, read and written from the main actor. A non-Sendable scope
// type fails to compile here in the Swift 6 language mode, so this locks in what the
// macro guide recommends.
@KeychainScope(service: "dev.test.compile.sendable")
private final class SendableClassScope: Sendable {
    @KeychainItem("item")
    var item: String?
}

@KeychainScope(service: "dev.test.compile.main-actor")
@MainActor private final class MainActorScope {
    @KeychainItem("item")
    var item: String?
}

@KeychainScope(service: "dev.test.compile.actor")
private actor ActorScope {
    @KeychainItem("item")
    var item: String?

    @KeychainItem("count")
    var count: Int
}

@MainActor
private func useScopesFromTheMainActor() async throws {
    _ = try await ScopeWithoutAccessGroup().item
    try await ScopeWithoutAccessGroup().setItem(nil)
    _ = try await SendableClassScope().item
    try await SendableClassScope().setItem(nil)
    _ = try await MainActorScope().item
    try await MainActorScope().setItem(nil)
    _ = try await ActorScope().item
    try await ActorScope().setItem(nil)
    try await ActorScope().setCount(1)
    try await ActorScope.deleteAll()
}

@Test
func keychainScopeDeleteAllIsStatic() async throws {
    // Verify deleteAll() is callable as a static method (no instance needed).
    // Actual keychain access is skipped; we only confirm the call compiles.
    _ = ScopeWithoutAccessGroup.deleteAll
    _ = ScopeWithAccessGroup.deleteAll
    _ = ClassScope.deleteAll
    _ = useScopesFromTheMainActor
}
