#!/usr/bin/env bash
# Runs DataProtectionIntegrationTests inside a host app, so the real keychain sees an
# app's entitlements. SwiftPM test bundles have none, so the keychain rejects them.
#
# Usage: scripts/run-keychain-host-tests.sh ios|macos
#
#   ios    Ad-hoc signed on iOS simulators. Set SIMULATOR_IDS to a space-separated list of
#          UDIDs to choose them; otherwise SIMULATOR_COUNT (default 2) selects that many
#          iPhones from the newest iOS runtime or SIMULATOR_RUNTIME (e.g. 26.4).
#   macos  The data-protection store. Needs an Apple Development identity and
#          DEVELOPMENT_TEAM; Xcode creates the development profile on first run.
#
# Needs XcodeGen. DERIVED_DATA_PATH overrides the build location. RESULT_BUNDLE_PATH
# optionally specifies an xcresult path for the iOS tests.
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
        simulator_count="${SIMULATOR_COUNT:-2}"
        if ! [[ "$simulator_count" =~ ^[1-9][0-9]*$ ]]; then
            echo "error: SIMULATOR_COUNT must be a positive integer" >&2
            exit 64
        fi
        ids="${SIMULATOR_IDS:-$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
runtimes = [name for name in devices if ".SimRuntime.iOS-" in name and devices[name]]
if sys.argv[2]:
    runtimes = [name for name in runtimes if name.endswith(".SimRuntime.iOS-" + sys.argv[2].replace(".", "-"))]
runtimes.sort(key=lambda name: [int(part) for part in name.rsplit("iOS-", 1)[1].split("-")])
phones = [d["udid"] for d in devices[runtimes[-1]] if d["name"].startswith("iPhone")] if runtimes else []
print(" ".join(phones[:int(sys.argv[1])]))
' "$simulator_count" "${SIMULATOR_RUNTIME:-}")}"
        if [[ -z "$ids" ]]; then
            echo "error: no available iPhone simulator for runtime ${SIMULATOR_RUNTIME:-latest}" >&2
            exit 1
        fi
        destinations=()
        count=0
        for id in $ids; do
            destinations+=(-destination "platform=iOS Simulator,id=$id")
            count=$((count + 1))
        done
        if [[ -z "${SIMULATOR_IDS:-}" && $count -lt $simulator_count ]]; then
            echo "warning: found $count of $simulator_count requested iPhone simulators" >&2
        fi
        parallel_testing=YES
        if [[ $count -eq 1 ]]; then
            parallel_testing=NO
        fi
        xcodebuild build-for-testing \
            -project "$host/KeychainHost.xcodeproj" \
            -scheme KeychainHost-iOS \
            "${destinations[@]}" \
            -derivedDataPath "$derived" \
            OTHER_SWIFT_FLAGS="$trait_flags"
        for id in $ids; do
            python3 -c '
import subprocess, sys
try:
    subprocess.run(["xcrun", "simctl", "bootstatus", sys.argv[1], "-b"], check=True, timeout=180)
except subprocess.TimeoutExpired:
    sys.exit("error: simulator " + sys.argv[1] + " did not boot within 180 seconds")
' "$id"
        done
        result_args=()
        if [[ -n "${RESULT_BUNDLE_PATH:-}" ]]; then
            result_args=(-resultBundlePath "$RESULT_BUNDLE_PATH")
        fi
        xcodebuild test-without-building \
            -project "$host/KeychainHost.xcodeproj" \
            -scheme KeychainHost-iOS \
            "${destinations[@]}" \
            -parallel-testing-enabled "$parallel_testing" \
            -parallel-testing-worker-count "$count" \
            -derivedDataPath "$derived" \
            ${result_args[@]+"${result_args[@]}"} \
            OTHER_SWIFT_FLAGS="$trait_flags"
        if [[ -n "${RESULT_BUNDLE_PATH:-}" ]]; then
            xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE_PATH" --format json | python3 -c '
import json, sys
result = json.load(sys.stdin)
if result["passedTests"] == 0:
    sys.exit("error: no keychain integration tests passed")
print("Keychain integration tests passed:", result["passedTests"])
'
        fi
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
