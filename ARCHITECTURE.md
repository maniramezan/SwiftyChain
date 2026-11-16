# Architecture

The public overview lives in [Architecture](Sources/SwiftyChain/Documentation.docc/Articles/Architecture.md).

## Modules and contract

`SwiftyChainCore` defines public values and the public `KeychainBackend` contract, re-exported
by `SwiftyChain`. `Keychain`, `KeychainStorage`, and `SwiftyChainTesting.InMemoryKeychain`
use `KeychainEngine` for serialization, validation, writes, and observation.

```text
Keychain actor ─┐
KeychainStorage ┼→ KeychainEngine → KeychainBackend → AppleKeychainBackend
InMemoryKeychain┘                                 ├→ SecretServiceBackend
                                                  ├→ InMemoryKeychainBackend
                                                  └→ UnsupportedPlatformBackend
```

`KeychainQuery` selects items; `KeychainAttributes` holds write policy and data. Backends
implement add, data, contains, accounts, update, and delete, and declare
`KeychainBackendCapabilities`. Query validation depends on the operation. Linux's NUL
rejection remains in its backend because it is a restriction on C string values.
Cryptographic operations use the public `KeychainCryptoBackend` refinement when the
`cryptography` trait and Security framework are available.

`nil` query attributes match any value. Synchronizable `nil` matches local and synchronized
items; `false` matches local items only. Add throws on duplicates, read and update throw on
missing items, and delete succeeds for missing items. Optional write attributes use platform
defaults on add and preserve existing policy on update. Write policy does not affect key identity.

## Concurrency and observation

Where Dispatch is available, every `Keychain` actor uses one dedicated serial
`KeychainExecutor` queue. Blocking Security and libsecret calls stay off the cooperative pool.
WASI uses the default executor. `KeychainStorage` remains synchronous on its caller's thread,
while sharing the engine's validation and observation behavior.

With `observation`, platform-backed engines share a process-wide observer registry. Custom
backends get a registry per engine, even when two engines share the same backend object.
Generic-password events name a service; internet-password events name a server.

`SecretServiceClient` serializes libsecret calls process-wide. A deadline includes time waiting
for another call. Updates change items in their existing collection and attempt rollback after
partial failure. Failed connections drop the cached proxy; a stale connection can be retried
once. Separate processes can still race when creating Secret Service items.

## Apple stores and access control

The macOS default is the legacy login keychain, including `Keychain.shared`.
`KeychainConfiguration(macOSStore: .dataProtection)` opts in to a separate data-protection
store; it does not migrate items. That backend puts `kSecUseDataProtectionKeychain` on every
query, including crypto queries. Accessibility is ignored by the legacy store; ACL dialogs
can still block it. Other Apple platforms already use data protection.

`KeychainAccessControl` creates a `SecAccessControl` object in place of `kSecAttrAccessible`.
The policy uses the system prompt; there is no `LAContext` API. Linux, tvOS, and the macOS
legacy store reject access control. tvOS also rejects synchronizable requests because its
keychain never syncs through iCloud. Apple capabilities reflect the OS and configuration.

`saveCryptoKey` throws on duplicates. `upsertCryptoKey` adds or updates in place and never
uses delete-and-add. The macOS legacy store rejects material replacement: experimental
updates either failed or reported success while reads retained the original material. Use
the data-protection store for updates. Non-exportable replacement material is rejected.

## Verification

Contract fixtures cover memory, Linux emulation, and opted-in real platform backends.
`InMemoryKeychain(emulating: .linux)` reproduces capability restrictions without a daemon.
Apple data-protection and access-control behavior needs a signed, entitled host; ordinary
package tests verify query construction only. Linux daemon scenarios and WASI builds run in CI.
`operationFailed(Int32)` retains platform-specific Security or libsecret/GLib codes.
