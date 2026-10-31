#!/usr/bin/env bash
# viii-fixes-20261031a
#   1. matugen "Permission denied": GTK4 gtk.css was a symlink into /usr/share (root-owned)
#   2. Settings gear reachable from the keyboard in the hub (Up to the tabs, Right past Library, Enter)
#   3. charging indicator (green fill + bolt) in the hub top bar
# Does NOT touch install.sh or ~/.config/hypr. Backup: ~/viii-shell-3/.bak-fixes-<stamp>/
set -u
P="$HOME/viii-shell-3"
PAY="$P/.payload-fixes-20261031a"
BAK="$P/.bak-fixes-$(date +%Y%m%d-%H%M%S)"
FILES="matugen/config.toml bin/viii-theme quickshell/hub/Hub.qml quickshell/hub/TopBar.qml"

die() { echo "FAILED: $*"; exit 1; }
[ -d "$P" ] || die "no $P"
[ -f "$PAY/apply.pl" ] || die "payload missing (already installed?)"
for f in $FILES; do [ -f "$P/$f" ] || die "missing $P/$f"; done

mkdir -p "$BAK" || die "backup dir"
for f in $FILES; do mkdir -p "$BAK/$(dirname "$f")"; cp -a "$P/$f" "$BAK/$f" || die "backup $f"; done
restore() { for f in $FILES; do cp -a "$BAK/$f" "$P/$f"; done; echo "rolled back from $BAK"; }

perl "$PAY/apply.pl" "$P" || { echo "patch refused: a file differs from what I expected. Nothing was changed."; exit 1; }

# brace balance must be unchanged by the patch
bal() { echo $(( $(tr -cd '{' < "$1" | wc -c) - $(tr -cd '}' < "$1" | wc -c) )); }
for f in quickshell/hub/Hub.qml quickshell/hub/TopBar.qml; do
  [ "$(bal "$BAK/$f")" = "$(bal "$P/$f")" ] || { echo "brace balance changed in $f"; restore; exit 1; }
done
bash -n "$P/bin/viii-theme" || { echo "viii-theme syntax error"; restore; exit 1; }
chmod +x "$P/bin/viii-theme"
grep -q 'viii-colors.css' "$P/matugen/config.toml" || { restore; die "config.toml not patched"; }
grep -q 'gearFocus' "$P/quickshell/hub/Hub.qml" || { restore; die "Hub.qml not patched"; }
grep -q 'UPowerDeviceState' "$P/quickshell/hub/TopBar.qml" || { restore; die "TopBar.qml not patched"; }
echo "QML + config patched."

echo "Re-running viii-theme to check that matugen works now..."
if "$P/bin/viii-theme"; then
  echo "matugen: OK. gtk-4.0/gtk.css is now: $(head -c 120 "$HOME/.config/gtk-4.0/gtk.css" 2>/dev/null | tr '\n' ' ')"
else
  echo "WARNING: viii-theme still fails (the QML fixes are installed anyway). Send: bash -c 'viii-theme 2>&1 | wl-copy'"
fi

rm -rf "$PAY"
echo "Backup: $BAK"
echo "Done. Now run: viii restart"
