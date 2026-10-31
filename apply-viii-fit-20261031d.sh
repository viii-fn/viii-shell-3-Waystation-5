#!/usr/bin/env bash
# viii-fit-20261031d: Settings, Wallstore, Control Center and the home row keep their layout on any screen shape
# (16:10, 4:3, ultrawide). Anchor patches only; backs up every file; rolls back on any failure. Never touches install.sh or hypr.
set -u
ROOT="$HOME/viii-shell-3"
QS="$ROOT/quickshell"
PAY="$ROOT/.payload-fit-20261031d"
BAK="$ROOT/.bak-fit-$(date +%Y%m%d-%H%M%S)"
die() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$QS" ] || die "$QS not found"
[ -f "$PAY/apply.pl" ] || die "payload $PAY not found (re-extract the tar)"
FILES="hub/Hub.qml hub/WallstorePage.qml hub/Backdrop.qml cc/ControlCenter.qml settings/SettingsPage.qml"
for f in $FILES; do [ -f "$QS/$f" ] || die "missing $QS/$f"; done
grep -q "NotifHistoryPage" "$QS/hub/Hub.qml" || echo "note: notifs-20261031c is not installed; this package does not need it."

for f in $FILES; do mkdir -p "$BAK/quickshell/$(dirname "$f")"; cp -a "$QS/$f" "$BAK/quickshell/$f"; done
rollback() { cp -a "$BAK/quickshell/." "$QS/"; echo "ROLLED BACK to the backup in $BAK" >&2; exit 1; }

perl "$PAY/apply.pl" "$QS" || { echo "Patch refused, nothing was written." >&2; exit 1; }

for f in $FILES; do
  o=$(tr -cd '{' < "$QS/$f" | wc -c); c=$(tr -cd '}' < "$QS/$f" | wc -c)
  [ "$o" -eq "$c" ] || { echo "brace check failed in $f ($o/$c)" >&2; rollback; }
done
rm -rf "$PAY"
echo "OK: viii-fit-20261031d installed. Backup: $BAK"
