# Contributing

## Prerequisites

Swift 6.3 or newer is required. Install via [swiftly](https://swiftlang.github.io/swiftly/) if needed:

```bash
swiftly install 6.3
swiftly use 6.3
swift --version  # should print 6.3.x
```

## Fork & Branch

```bash
git clone https://github.com/<your-fork>/SwiftyChain.git
cd SwiftyChain
git checkout -b feature/<short-description>
```

## Build

```bash
swift build
```

## Test

```bash
# Fast — no keychain entitlement needed:
swift test --filter SwiftyChainTests
swift test --filter SwiftyChainMacrosTests

# Full suite with coverage:
swift test --enable-code-coverage

# With optional traits:
swift test --traits "observation,cryptography"

# Integration tests against the real keychain (macOS only):
SWIFTYCHAIN_RUN_KEYCHAIN_INTEGRATION=1 swift test --filter SwiftyChainTests
```

### Coverage Targets

CI enforces a minimum of **80% overall line coverage**. Measure with:

```bash
swift test --enable-code-coverage
xcrun llvm-cov report \
  .build/debug/SwiftyChainPackageTests.xctest/Contents/MacOS/SwiftyChainPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  --ignore-filename-regex='.build|Tests'
```

## Format

`swift-format` lint must pass with zero violations before merging:

```bash
swift-format lint --recursive --strict Sources Tests
# Auto-fix (review changes before committing):
swift-format format --recursive --in-place Sources Tests
```

## Security Requirements

All contributions must uphold these invariants:

1. **No in-memory caching** — every read hits the keychain directly.
2. **No logging of values** — errors may log `OSStatus` codes but never the secret value or its `Data`.
3. **Strict Sendable** — no shared mutable state outside the `Keychain` actor.
4. **Explicit accessibility** — `KeychainAccessibility` is always set; no silent fallback to insecure defaults.
5. **No force unwrap** — all `CFTypeRef` casts use `as?` with typed error throws; `!` is never used.

## Pull Requests

Before opening a PR:

1. `swift-format lint --recursive --strict Sources Tests` — zero violations.
2. All existing tests pass.
3. New behaviour has tests; overall coverage stays at or above thresholds.
4. DocC comments updated for any changed public API.
5. Open PR against `main`; CI runs automatically.

## Out of Scope (v1.0)

The following are **not** accepted in v1.0:

- **Windows / Linux support** — `Security.framework` does not exist there. The `SecureStorageBackend` protocol keeps the door open for a future `WindowsCredentialBackend` in v2.0.
- **`kSecClassCertificate` / `kSecClassIdentity`** — planned v1.1+ based on user demand.
- **Keychain migration utilities** — planned v1.1+ (bulk-migrate items between services/accounts/formats).
- **macOS-only legacy keychain APIs** (`SecKeychainCreate`, ACLs) — use `SecItem*` uniformly.

## Code of Conduct

This project follows the [Swift Code of Conduct](https://www.swift.org/code-of-conduct/).
