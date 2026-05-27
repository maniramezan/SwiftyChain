# Security Policy

## Supported Versions

Only the latest release on `main` receives security fixes.

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |
| Older   | No        |

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Report vulnerabilities by email to **mani.ramezan@gmail.com** with:

- A description of the vulnerability and its potential impact.
- Steps to reproduce or proof-of-concept code.
- Any suggested mitigations, if known.

You can expect an acknowledgement within **72 hours** and a status update within **7 days**. If a fix is needed, a patched release will be coordinated before public disclosure.

## Security Design Invariants

SwiftyChain upholds these invariants in every release:

1. **No in-memory caching** — every read hits the keychain directly; values are never retained between calls.
2. **No value logging** — errors may log `OSStatus` codes but never the secret value or its `Data` representation.
3. **Strict Sendable** — no shared mutable state outside the `Keychain` actor boundary.
4. **Explicit accessibility** — `KeychainAccessibility` is always set; no silent fallback to insecure defaults.
5. **No force unwraps** — all `CFTypeRef` casts use `as?` with typed error throws.
