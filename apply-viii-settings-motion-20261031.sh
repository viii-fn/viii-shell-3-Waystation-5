#!/usr/bin/env bash
# VIII PS5 Settings v3 — motion + performance pass (animations, coalesced writes, no offscreen buffers).
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${HOME}/viii-shell-3"
PAYLOAD="${SCRIPT_DIR}/.viii-settings-motion-payload-20261031/quickshell"
CHECKER="${SCRIPT_DIR}/.check-viii-settings-qml.pl"
STAMP="$(date +%Y%m%d-%H%M%S)-${BASHPID}"
BACKUP="${PROJECT}/.bak-settings-motion-${STAMP}"
FILES=(
  "settings/SettingsPage.qml"
  "hub/Hub.qml"
  "hub/TopBar.qml"
)
NEW_FILES=()
INSTALL_OK=0

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -d "${PROJECT}/quickshell" ]] || fail "Project not found at ${PROJECT}/quickshell"
[[ -f "${PROJECT}/quickshell/hub/Hub.qml" ]] || fail "Hub.qml is missing."
[[ -f "${PROJECT}/quickshell/hub/TopBar.qml" ]] || fail "TopBar.qml is missing."
[[ -f "${PROJECT}/quickshell/settings/SettingsPage.qml" ]] || fail "SettingsPage.qml is missing. Install the previous Settings package first."
command -v perl >/dev/null 2>&1 || fail "Perl is required for the structural validation."
[[ -f "${CHECKER}" ]] || fail "QML structure checker is missing."

for file in "${FILES[@]}"; do
  [[ -f "${PAYLOAD}/${file}" ]] || fail "Package payload is missing ${file}."
done

# Validate the payload before touching the project.
perl "${CHECKER}" \
  "${PAYLOAD}/settings/SettingsPage.qml" \
  "${PAYLOAD}/hub/Hub.qml" \
  "${PAYLOAD}/hub/TopBar.qml"

if grep -nE 'nmtui|nwg-displays|kitty|yay|pcmanfm|textAlign:' "${PAYLOAD}/settings/SettingsPage.qml"; then
  fail "An external settings UI or unsupported property remains in SettingsPage.qml."
fi

grep -q 'import Quickshell.Networking' "${PAYLOAD}/settings/SettingsPage.qml" \
  || fail "Native Quickshell Networking integration is missing."
grep -q 'Keys.onPressed' "${PAYLOAD}/settings/SettingsPage.qml" \
  || fail "Settings keyboard handler is missing."
grep -q 'settings.forceActiveFocus();' "${PAYLOAD}/hub/Hub.qml" \
  || fail "Hub does not hand keyboard focus to Settings."
grep -q 'Behavior on reveal' "${PAYLOAD}/settings/SettingsPage.qml" \
  || fail "Settings transition animation is missing."
grep -q 'contentTransition' "${PAYLOAD}/settings/SettingsPage.qml" \
  || fail "Category transition animation is missing."
grep -q 'model: root.currentRows.length' "${PAYLOAD}/settings/SettingsPage.qml" \
  || fail "Count-keyed row model (no-rebuild optimisation) is missing."
grep -q 'briFlush' "${PAYLOAD}/settings/SettingsPage.qml" \
  || fail "Coalesced brightness writes are missing."

mkdir -p "${BACKUP}"

rollback() {
  local status=$?
  trap - EXIT ERR
  if (( INSTALL_OK == 0 )); then
    printf '\nInstallation failed. Restoring the previous Settings files...\n' >&2
    for file in "${NEW_FILES[@]}"; do
      rm -f "${PROJECT}/quickshell/${file}"
    done
    if [[ -d "${BACKUP}" ]]; then
      cp -a "${BACKUP}/." "${PROJECT}/"
    fi
    printf 'Rollback complete. Backup: %s\n' "${BACKUP}" >&2
  fi
  exit "$status"
}
trap rollback EXIT

for file in "${FILES[@]}"; do
  target="${PROJECT}/quickshell/${file}"
  if [[ -e "${target}" ]]; then
    mkdir -p "${BACKUP}/quickshell/$(dirname "${file}")"
    cp -a "${target}" "${BACKUP}/quickshell/${file}"
  else
    NEW_FILES+=("${file}")
  fi
  install -D -m 644 "${PAYLOAD}/${file}" "${target}"
done

# Validate the installed files and assert the no-external-settings-UI rule.
perl "${CHECKER}" \
  "${PROJECT}/quickshell/settings/SettingsPage.qml" \
  "${PROJECT}/quickshell/hub/Hub.qml" \
  "${PROJECT}/quickshell/hub/TopBar.qml"

if grep -nE 'nmtui|nwg-displays|kitty|yay|pcmanfm|textAlign:' \
  "${PROJECT}/quickshell/settings/SettingsPage.qml"; then
  fail "Post-install validation found an external settings UI or unsupported property."
fi

grep -q 'settings.forceActiveFocus();' "${PROJECT}/quickshell/hub/Hub.qml" \
  || fail "Post-install keyboard focus validation failed."
grep -q 'import Quickshell.Networking' "${PROJECT}/quickshell/settings/SettingsPage.qml" \
  || fail "Post-install native networking validation failed."

rm -rf "${SCRIPT_DIR}/.viii-settings-motion-payload-20261031" "${CHECKER}"
INSTALL_OK=1
trap - EXIT ERR

printf '\nVIII PS5 Settings v3 (motion) installed successfully.\n'
printf 'Backup: %s\n' "${BACKUP}"
printf '\nRestart the shell when ready:\n  viii restart\n'
