#!/usr/bin/env bash
# viii-notifs-20261031b: PS5-style notification toasts + notification history + instant charger plug/unplug events.
# New files: quickshell/core/Notifs.qml, quickshell/notif/NotifPopup.qml.
# Patched:   quickshell/shell.qml (import + one Variants block), quickshell/core/qmldir (one line).
# Does NOT touch install.sh or ~/.config/hypr. Backup: ~/viii-shell-3/.bak-notifs-<stamp>/
set -u
P="$HOME/viii-shell-3"
PAY="$P/.payload-notifs-20261031b"
BAK="$P/.bak-notifs-$(date +%Y%m%d-%H%M%S)"
PATCHED="quickshell/shell.qml quickshell/core/qmldir"
NEWF="quickshell/core/Notifs.qml quickshell/notif/NotifPopup.qml"

die() { echo "FAILED: $*"; exit 1; }
[ -d "$P" ] || die "no $P"
[ -f "$PAY/apply.pl" ] && [ -f "$PAY/Notifs.qml" ] && [ -f "$PAY/NotifPopup.qml" ] || die "payload missing (already installed?)"
for f in $PATCHED; do [ -f "$P/$f" ] || die "missing $P/$f"; done
grep -q 'Notifs' "$P/quickshell/core/qmldir" && die "core/qmldir already mentions Notifs (already installed?)"

# another daemon would own org.freedesktop.Notifications and win; warn, don't stop
for d in mako dunst swaync fnott wired deadd-notification-center xfce4-notifyd; do
  pgrep -x "$d" >/dev/null 2>&1 && echo "WARNING: $d is running; only one notification daemon can run. Stop it, or toasts will not appear."
done

mkdir -p "$BAK" || die "backup dir"
for f in $PATCHED; do mkdir -p "$BAK/$(dirname "$f")"; cp -a "$P/$f" "$BAK/$f" || die "backup $f"; done
rollback() {
  for f in $PATCHED; do cp -a "$BAK/$f" "$P/$f"; done
  rm -f "$P/quickshell/core/Notifs.qml" "$P/quickshell/notif/NotifPopup.qml"
  rmdir "$P/quickshell/notif" 2>/dev/null
  echo "rolled back from $BAK"
}

# check the payload BEFORE touching the project
bal() { echo $(( $(tr -cd '{' < "$1" | wc -c) - $(tr -cd '}' < "$1" | wc -c) )); }
for f in "$PAY/Notifs.qml" "$PAY/NotifPopup.qml"; do
  [ "$(bal "$f")" = "0" ] || die "payload $(basename "$f") has unbalanced braces (nothing changed)"
  if grep -nE 'layer\.enabled|ShaderEffect|MultiEffect|DropShadow|RectangularShadow|smooth: *false|antialiasing: *true|blur' "$f"; then die "performance rule violated in $(basename "$f") (nothing changed)"; fi
  if grep -nE 'interval: *([0-9]|1[0-5])([^0-9]|$)' "$f"; then die "Timer under 16 ms in $(basename "$f") (nothing changed)"; fi
  if grep -nE '^[[:space:]]*Behavior on' "$PAY/Notifs.qml"; then die "Behavior inside a singleton (Qt 6.12 crash)"; fi
done

perl "$PAY/apply.pl" "$P" || { echo "patch refused: shell.qml or core/qmldir differs from what I expected. Nothing was changed."; exit 1; }

mkdir -p "$P/quickshell/notif" || { rollback; die "mkdir notif"; }
cp "$PAY/Notifs.qml" "$P/quickshell/core/Notifs.qml" && cp "$PAY/NotifPopup.qml" "$P/quickshell/notif/NotifPopup.qml" || { rollback; die "copy failed"; }

[ "$(bal "$BAK/quickshell/shell.qml")" = "$(bal "$P/quickshell/shell.qml")" ] || { echo "brace balance changed in shell.qml"; rollback; exit 1; }
grep -q 'import "notif"' "$P/quickshell/shell.qml" && grep -q 'NotifPopup' "$P/quickshell/shell.qml" || { rollback; die "shell.qml not patched"; }
grep -q 'singleton Notifs 1.0 Notifs.qml' "$P/quickshell/core/qmldir" || { rollback; die "qmldir not patched"; }

rm -rf "$PAY"
echo "Notifications installed. Backup: $BAK"
echo "Now run: viii restart"
echo "Then test:  notify-send 'Hello' 'This is a test'   (and plug / unplug the charger)"
