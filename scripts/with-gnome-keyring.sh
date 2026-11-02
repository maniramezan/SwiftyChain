#!/usr/bin/env bash
# Runs a command in a private D-Bus session with an unlocked GNOME Keyring, for
# exercising SwiftyChain's Secret Service backend on Linux.
#
# Usage: scripts/with-gnome-keyring.sh swift test
#
# Needs libsecret-1-0, gnome-keyring, dbus-x11, and procps (or your distribution's
# equivalents). Only the keyring daemons this script starts are stopped when the
# command exits — even if the command froze them — so a desktop session's own
# keyring daemon is never touched.
set -euo pipefail

if [ -z "${SWIFTYCHAIN_KEYRING_SESSION:-}" ]; then
    exec env SWIFTYCHAIN_KEYRING_SESSION=1 dbus-run-session -- "$0" "$@"
fi

# pkill/pgrep match the process comm name, which the kernel truncates to
# 15 characters: gnome-keyring-d.
snap_daemon_pids() {
    pgrep -x gnome-keyring-d | sort -u || true
}

daemon_pids_on_entry="$(snap_daemon_pids)"

# Lists the daemons started under this script: the ones present now that were
# not there when the script entered.
new_daemon_pids() {
    comm -13 <(printf '%s\n' "${daemon_pids_on_entry[@]}" | sort -u) <(snap_daemon_pids)
}

stop_keyring() {
    local pids
    pids="$(new_daemon_pids)"
    if [ -z "$pids" ]; then
        return
    fi
    # The CI timeout test freezes its daemon with SIGSTOP; resume it so it can exit.
    xargs -r kill -CONT <<< "$pids" 2>/dev/null || true
    xargs -r kill <<< "$pids" 2>/dev/null || true
}
trap stop_keyring EXIT

echo -n "${SWIFTYCHAIN_KEYRING_PASSWORD:-swiftychain}" \
    | gnome-keyring-daemon --unlock --components=secrets > /dev/null 2>&1

# The daemon unlocks the keyring asynchronously. Wait until the default collection
# reports itself unlocked so the command never races the unlock.
for _ in $(seq 1 100); do
    locked=$(dbus-send --session --print-reply --dest=org.freedesktop.secrets \
        /org/freedesktop/secrets/aliases/default \
        org.freedesktop.DBus.Properties.Get \
        string:org.freedesktop.Secret.Collection string:Locked 2> /dev/null || true)
    if [[ "$locked" == *"boolean false"* ]]; then
        "$@"
        exit $?
    fi
    sleep 0.1
done

echo "GNOME Keyring did not unlock its default collection within 10 seconds" >&2
exit 1
