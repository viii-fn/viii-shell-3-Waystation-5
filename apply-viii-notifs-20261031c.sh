#!/usr/bin/env bash
# viii-notifs-20261031c: PS5-style toast, notification history page (bell + SUPER+N), OSD/toast scale with the screen.
# Backs up every file it touches, checks everything first, rolls back on any failure. Never touches install.sh or hypr.
set -u
ROOT="$HOME/viii-shell-3"
QS="$ROOT/quickshell"
PAY="$ROOT/.payload-notifs-20261031c"
BAK="$ROOT/.bak-notifs-c-$(date +%Y%m%d-%H%M%S)"
die() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$QS" ] || die "$QS not found"
[ -d "$PAY" ] || die "payload $PAY not found (re-extract the tar)"
FILES="shell.qml core/Desk.qml hub/Hub.qml hub/TopBar.qml notif/NotifPopup.qml cc/Osd.qml"
for f in $FILES; do [ -f "$QS/$f" ] || die "missing $QS/$f"; done

bash "$PAY/check.sh" "$PAY/NotifPopup.qml" "$PAY/Osd.qml" "$PAY/NotifHistoryPage.qml" || die "payload check failed, nothing changed"

for f in $FILES; do mkdir -p "$BAK/quickshell/$(dirname "$f")"; cp -a "$QS/$f" "$BAK/quickshell/$f"; done

rollback() {
  cp -a "$BAK/quickshell/." "$QS/"
  rm -f "$QS/hub/NotifHistoryPage.qml"
  echo "ROLLED BACK to the backup in $BAK" >&2
  exit 1
}

perl "$PAY/apply.pl" "$QS" || { echo "Patch refused, nothing was written." >&2; exit 1; }

cp "$PAY/NotifPopup.qml" "$QS/notif/NotifPopup.qml" || rollback
cp "$PAY/Osd.qml" "$QS/cc/Osd.qml" || rollback
cp "$PAY/NotifHistoryPage.qml" "$QS/hub/NotifHistoryPage.qml" || rollback

for f in $FILES hub/NotifHistoryPage.qml; do
  o=$(tr -cd '{' < "$QS/$f" | wc -c); c=$(tr -cd '}' < "$QS/$f" | wc -c)
  [ "$o" -eq "$c" ] || { echo "brace check failed in $f ($o/$c)" >&2; rollback; }
done

rm -rf "$PAY"
echo "OK: viii-notifs-20261031c installed. Backup: $BAK"
