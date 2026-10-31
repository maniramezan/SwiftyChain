# Architecture

How SwiftyChain keeps one public API on top of different platform keychains.

## Overview

SwiftyChain separates what your code calls from where secrets are stored. The public API,
``Keychain``, ``KeychainStorage``, and the macros, sits on a shared engine that talks to
storage only through a single backend contract. Each platform implements that contract,
so the same calls behave the same way everywhere.

| Module | Role |
|---|---|
| `SwiftyChainCore` | The public value types (``KeychainKey``, ``KeychainError``, ``KeychainStorable``, and so on) and the backend contract. `SwiftyChain` re-exports it, so you never import it directly. |
| `SwiftyChain` | The public API and the engine that turns each call into backend queries. |
| `SwiftyChainAppleKeychain` | The Apple backend, built on the Security framework. |
| `SwiftyChainSecretService` | The Linux backend, built on libsecret, which is loaded at runtime. |
| `SwiftyChainTesting` | `InMemoryKeychain` and `InMemoryKeychainBackend`, built on an in-memory backend. |

### The backend contract

Every backend implements the same small set of operations: add, copy matching items,
update, and delete. They share these rules:

- An attribute left unset in a query matches any value.
- Adding an item that already exists throws ``KeychainError/duplicateItem``.
- Reading or updating a missing item throws ``KeychainError/itemNotFound``.
- Deleting removes every matching item and succeeds when nothing matches.
- Platform diagnostics are logged, never carried in the thrown error.

Each backend also declares its capabilities: synchronizable items, access groups,
accessibility policies, internet passwords, and cryptographic keys. Before any call
reaches a backend, the engine checks the query against those capabilities in one place.
An option the platform can't honor fails with ``KeychainError/platformUnsupported(_:)``,
worded the same way on every platform, instead of being silently ignored. Accessibility
is the one option a backend may ignore, because it only narrows when an item is readable.

### One test suite for every backend

Because `InMemoryKeychain` runs the same engine over an in-memory backend, tests that use it
exercise the same lookup, duplicate, and bulk-delete rules as production. SwiftyChain's own
contract test suite runs against every backend: in-memory on every build, the real Apple
Keychain, and GNOME Keyring on Linux CI.

### Platforms without a backend

On a platform with no keychain backend, every call throws
``KeychainError/platformUnsupported(_:)``. Code that uses SwiftyChain still compiles there,
and fails clearly at runtime instead of storing secrets insecurely.
