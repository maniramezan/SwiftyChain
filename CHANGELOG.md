# Changelog

All notable changes to SwiftyChain are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- `deleteAllItems(matching:)` now correctly uses `kSecAttrServer` (not `kSecAttrService`) when bulk-deleting internet-password items.
- `observeKeychainChanges(service:accessGroup:)` now correctly filters events by `accessGroup`; previously observers received events for all access groups under a service.
- `loadCryptoKey(keyRef:)` no longer force-casts the `CFTypeRef` result; it now throws `KeychainError.unexpectedData` on type mismatch.

### Changed
- `Keychain.delete(key:)` and `deleteInternetPassword(for:)` are documented as no-ops when the item does not exist, matching their actual behaviour.
- `@KeychainItem` documentation corrected to show the generated async accessor API (`setXxx(_:)` peer method and `get async throws` getter) instead of the incorrect synchronous assignment syntax.
- `@KeychainStorage` documentation and README examples no longer reference a `defaultValue:` parameter that does not exist.
- tvOS platform note no longer incorrectly implies biometric authentication support.
- Crypto testing snippet in `Testing.md` updated to match the actual `CryptoKeyReference` initializer (`tag: String`) and `StoredSecKey` wrapper.
- `SwiftyChainTesting` DocC is now published to GitHub Pages alongside the main `SwiftyChain` documentation.
- CONTRIBUTING.md coverage threshold aligned with the 80% line-coverage minimum enforced by CI.
- Added `SECURITY.md` and this `CHANGELOG.md`.
