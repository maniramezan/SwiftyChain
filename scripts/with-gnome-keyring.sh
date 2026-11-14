#!/usr/bin/env bash
# Runs a command in a private D-Bus session with an unlocked GNOME Keyring, for
# exercising SwiftyChain's Secret Service backend on Linux.
#
# Usage: scripts/with-gnome-keyring.sh swift test
#
# Needs libsecret-1-0, gnome-keyring, dbus-x11, and procps (or your distribution's
# equivalents). SwiftyChain's second-collection test also needs libsecret-tools.
#
# The keyring lives in a temporary data directory, so the run never reads or writes
# the keyrings in ~/.local/share/keyrings, and the directory is removed afterwards.
# Only the keyring daemons this script starts are stopped when the command exits —
# even if the command froze them — so other keyring daemons on the machine are never
# touched. The command can find those daemons with:
#
#     pgrep -f -- "--control-directory=$SWIFTYCHAIN_KEYRING_CONTROL_DIRECTORY"
#
# and restart them, keeping the keyring's contents, with:
#
#     "$SWIFTYCHAIN_KEYRING_SCRIPT" --restart-keyring
set -euo pipefail

own_daemon_pids() {
    pgrep -f -- "--control-directory=$SWIFTYCHAIN_KEYRING_CONTROL_DIRECTORY" || true
}

stop_daemons() {
    local pids
    pids="$(own_daemon_pids)"
    [ -n "$pids" ] || return 0
    # The CI timeout test freezes its daemon with SIGSTOP; resume it so it can exit.
    xargs -r kill -CONT <<< "$pids" 2>/dev/null || true
    xargs -r kill <<< "$pids" 2>/dev/null || true
    for _ in $(seq 1 50); do
        [ -n "$(own_daemon_pids)" ] || return 0
        sleep 0.1
    done
}

start_daemon() {
    XDG_DATA_HOME="$SWIFTYCHAIN_KEYRING_DATA_DIRECTORY" gnome-keyring-daemon "$@" --components=secrets \
        --control-directory="$SWIFTYCHAIN_KEYRING_CONTROL_DIRECTORY" > /dev/null
}

# The daemon unlocks the keyring asynchronously. Wait until the default collection
# reports itself unlocked so the command never races the unlock.
start_and_unlock() {
    echo -n "${SWIFTYCHAIN_KEYRING_PASSWORD:-swiftychain}" | start_daemon --login
    start_daemon --start
    for _ in $(seq 1 100); do
        locked=$(dbus-send --session --print-reply --dest=org.freedesktop.secrets \
            /org/freedesktop/secrets/aliases/default \
            org.freedesktop.DBus.Properties.Get \
            string:org.freedesktop.Secret.Collection string:Locked 2> /dev/null || true)
        if [[ "$locked" == *"boolean false"* ]]; then
            return 0
        fi
        sleep 0.1
    done
    echo "GNOME Keyring did not unlock its default collection within 10 seconds" >&2
    return 1
}

# Used by tests, from inside a session this script set up, to check that SwiftyChain
# recovers when the keyring daemon restarts.
if [ "${1:-}" = "--restart-keyring" ]; then
    : "${SWIFTYCHAIN_KEYRING_CONTROL_DIRECTORY:?--restart-keyring only works inside a with-gnome-keyring.sh session}"
    stop_daemons
    start_and_unlock
    exit 0
fi

if [ -z "${SWIFTYCHAIN_KEYRING_SESSION:-}" ]; then
    exec env SWIFTYCHAIN_KEYRING_SESSION=1 dbus-run-session -- "$0" "$@"
fi

keyring_root="$(mktemp -d)"
# The daemons carry this unique control directory on their command line, which tells
# them apart from every other gnome-keyring-daemon.
export SWIFTYCHAIN_KEYRING_CONTROL_DIRECTORY="$keyring_root/control"
export SWIFTYCHAIN_KEYRING_DATA_DIRECTORY="$keyring_root/data"
SWIFTYCHAIN_KEYRING_SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
export SWIFTYCHAIN_KEYRING_SCRIPT
mkdir -m 700 "$SWIFTYCHAIN_KEYRING_CONTROL_DIRECTORY" "$SWIFTYCHAIN_KEYRING_DATA_DIRECTORY"

cleanup() {
    stop_daemons
    rm -rf -- "$keyring_root"
}
trap cleanup EXIT

# If anything asks D-Bus to activate the Secret Service before the daemons claim it,
# the activated daemon must also keep its keyrings out of the user's home.
dbus-update-activation-environment XDG_DATA_HOME="$SWIFTYCHAIN_KEYRING_DATA_DIRECTORY"

start_and_unlock
"$@"
