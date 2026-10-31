#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${HOME}/viii-shell-3"
PAYLOAD="${SCRIPT_DIR}/.viii-settings-payload-20261031"
STAMP="$(date +%Y%m%d-%H%M%S)-${BASHPID}"
BACKUP="${PROJECT}/.bak-settings-${STAMP}"

FILES=(
  "quickshell/settings/SettingsPage.qml"
  "quickshell/hub/Hub.qml"
  "quickshell/hub/TopBar.qml"
  "quickshell/core/Desk.qml"
  "quickshell/core/qmldir"
  "quickshell/shell.qml"
)
NEW_FILES=()

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -d "${PROJECT}/quickshell/core" ]] || fail "Project not found at ${PROJECT}"
[[ -f "${PROJECT}/quickshell/hub/Hub.qml" ]] || fail "Hub.qml is missing."
[[ -f "${PROJECT}/quickshell/shell.qml" ]] || fail "shell.qml is missing."
[[ -x "$(command -v perl || true)" ]] || fail "Perl is required for the QML structure check."

for file in "${FILES[@]}"; do
  [[ -f "${PAYLOAD}/${file}" ]] || fail "Package payload is missing ${file}."
done

# Validate the supplied QML before touching the project.
perl "${SCRIPT_DIR}/.check-viii-settings-qml.pl" \
  "${PAYLOAD}/quickshell/settings/SettingsPage.qml" \
  "${PAYLOAD}/quickshell/hub/Hub.qml" \
  "${PAYLOAD}/quickshell/hub/TopBar.qml" \
  "${PAYLOAD}/quickshell/core/Desk.qml" \
  "${PAYLOAD}/quickshell/shell.qml"

mkdir -p "${BACKUP}"

rollback() {
  local status=$?
  trap - ERR
  if (( status != 0 )); then
    printf '\nInstallation failed. Restoring the previous files...\n' >&2
    for file in "${NEW_FILES[@]}"; do
      rm -f "${PROJECT}/${file}"
    done
    if [[ -d "${BACKUP}" ]]; then
      cp -a "${BACKUP}/." "${PROJECT}/"
    fi
    printf 'Rollback complete. Backup: %s\n' "${BACKUP}" >&2
  fi
  exit "$status"
}
trap rollback ERR

for file in "${FILES[@]}"; do
  target="${PROJECT}/${file}"
  if [[ -e "${target}" ]]; then
    mkdir -p "${BACKUP}/$(dirname "${file}")"
    cp -a "${target}" "${BACKUP}/${file}"
  else
    NEW_FILES+=("${file}")
  fi
  install -D -m 644 "${PAYLOAD}/${file}" "${target}"
done

# Validate the installed files and guard against duplicate registrations.
perl "${SCRIPT_DIR}/.check-viii-settings-qml.pl" \
  "${PROJECT}/quickshell/settings/SettingsPage.qml" \
  "${PROJECT}/quickshell/hub/Hub.qml" \
  "${PROJECT}/quickshell/hub/TopBar.qml" \
  "${PROJECT}/quickshell/core/Desk.qml" \
  "${PROJECT}/quickshell/shell.qml"

driver_count="$(grep -c '^ThemeDriver 1.0 ThemeDriver.qml$' "${PROJECT}/quickshell/core/qmldir" || true)"
if [[ "${driver_count}" != "1" ]]; then
  printf 'ERROR: Expected exactly one ThemeDriver registration; found %s.\n' "${driver_count}" >&2
  false
fi

shortcut_count="$(grep -c 'name: "settings"' "${PROJECT}/quickshell/shell.qml" || true)"
if [[ "${shortcut_count}" != "1" ]]; then
  printf 'ERROR: Expected exactly one settings global shortcut; found %s.\n' "${shortcut_count}" >&2
  false
fi

trap - ERR
rm -rf "${PAYLOAD}" "${SCRIPT_DIR}/.check-viii-settings-qml.pl"
printf '\nVIII Settings installed successfully.\n'
printf 'Backup: %s\n' "${BACKUP}"
printf '\nRestart the shell when ready:\n  viii restart\n'
