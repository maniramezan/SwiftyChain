#!/usr/bin/env bash
# Runs DataProtectionIntegrationTests inside a host app, so the real keychain sees an
# app's entitlements. SwiftPM test bundles have none, so the keychain rejects them.
#
# Usage: scripts/run-keychain-host-tests.sh ios|macos
#
#   ios    Ad-hoc signed, on up to two iOS simulators in parallel. Set SIMULATOR_IDS to a
#          space-separated list of UDIDs to choose them; otherwise the first two available
#          iPhones on the newest iOS runtime are used.
#   macos  The data-protection store. Needs an Apple Development identity and
#          DEVELOPMENT_TEAM; Xcode creates the development profile on first run.
#
# Needs XcodeGen. DERIVED_DATA_PATH overrides the build location.
set -euo pipefail

platform="${1:?usage: $0 ios|macos}"
root="$(cd "$(dirname "$0")/.." && pwd)"
host="$root/Tests/KeychainHost"
derived="${DERIVED_DATA_PATH:-$root/.build/keychain-host}"

xcodegen generate --spec "$host/project.yml" --project "$host" --quiet

# Package traits only add these compilation conditions, and xcodebuild has no trait flag.
# $(inherited) is an Xcode build-setting reference, not a shell expansion.
# shellcheck disable=SC2016
trait_flags='$(inherited) -DCryptography -DObservation'

case "$platform" in
    ios)
        ids="${SIMULATOR_IDS:-$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
runtimes = [name for name in devices if ".SimRuntime.iOS-" in name and devices[name]]
runtimes.sort(key=lambda name: [int(part) for part in name.rsplit("iOS-", 1)[1].split("-")])
phones = [d["udid"] for d in devices[runtimes[-1]] if d["name"].startswith("iPhone")] if runtimes else []
print(" ".join(phones[:2]))
')}"
        if [[ -z "$ids" ]]; then
            echo "error: no available iPhone simulator" >&2
            exit 1
        fi
        destinations=()
        count=0
        for id in $ids; do
            destinations+=(-destination "platform=iOS Simulator,id=$id")
            count=$((count + 1))
        done
        if [[ $count -lt 2 ]]; then
            echo "warning: only one iPhone simulator is available, so tests run on one destination" >&2
        fi
        xcodebuild test \
            -project "$host/KeychainHost.xcodeproj" \
            -scheme KeychainHost-iOS \
            "${destinations[@]}" \
            -parallel-testing-enabled YES \
            -parallel-testing-worker-count "$count" \
            -derivedDataPath "$derived" \
            OTHER_SWIFT_FLAGS="$trait_flags"
        ;;
    macos)
        : "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to the team ID of your Apple Development identity}"
        xcodebuild test \
            -project "$host/KeychainHost.xcodeproj" \
            -scheme KeychainHost-macOS \
            -destination 'platform=macOS' \
            -allowProvisioningUpdates \
            -derivedDataPath "$derived" \
            DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
            OTHER_SWIFT_FLAGS="$trait_flags"
        ;;
    *)
        echo "usage: $0 ios|macos" >&2
        exit 64
        ;;
esac
