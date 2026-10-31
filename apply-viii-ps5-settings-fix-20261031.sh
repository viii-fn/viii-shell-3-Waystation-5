#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${HOME}/viii-shell-3"
PAYLOAD="${SCRIPT_DIR}/.viii-settings-payload-20261031/quickshell/settings/SettingsPage.qml"
STAMP="$(date +%Y%m%d-%H%M%S)-${BASHPID}"
BACKUP="${PROJECT}/.bak-settings-align-${STAMP}"
TARGET="${PROJECT}/quickshell/settings/SettingsPage.qml"
CHECKER="${SCRIPT_DIR}/.check-viii-settings-qml.pl"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ -f "$TARGET" ]] || fail "SettingsPage.qml not found at ${TARGET}. Install the original Settings package first."
[[ -f "$PAYLOAD" ]] || fail "Corrected SettingsPage.qml payload is missing."
[[ -f "$CHECKER" ]] || fail "QML structure checker is missing."

# Validate the replacement before changing the live project.
perl "$CHECKER" "$PAYLOAD"
mkdir -p "$BACKUP/quickshell/settings"
cp -a "$TARGET" "$BACKUP/quickshell/settings/SettingsPage.qml"
restore() {
    local status=$?
    trap - ERR
    if (( status != 0 )); then
        cp -a "$BACKUP/quickshell/settings/SettingsPage.qml" "$TARGET"
        printf 'Patch failed; original file restored. Backup: %s\n' "$BACKUP" >&2
    fi
    exit "$status"
}
trap restore ERR
install -m 644 "$PAYLOAD" "$TARGET"
perl "$CHECKER" "$TARGET"
if grep -n 'textAlign:' "$TARGET"; then
    fail 'Unsupported textAlign property remains.'
fi
grep -q 'horizontalAlignment: Text.AlignRight' "$TARGET" || fail 'Right-alignment correction is missing.'
trap - ERR
printf 'Settings alignment fix applied successfully.\nBackup: %s\nRestart with: viii restart\n' "$BACKUP"
