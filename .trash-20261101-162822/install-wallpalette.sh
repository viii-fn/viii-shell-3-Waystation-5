#!/usr/bin/env bash
# viii-shell-3: the hub follows the wallpaper palette only (no per-app colours). Does NOT touch hypr.
set -u
Q="$HOME/viii-shell-3/quickshell"; F="$Q/core/Apps.qml"
grep -q 'Theme.wp' "$F" || { echo "Wallstore install not found (run install-wallstore.sh first)"; exit 1; }
cp "$F" "$F.bak-wallpalette" || exit 1
perl "$HOME/viii-shell-3/apply-wallpalette.pl" || { echo "FAILED, restoring"; cp "$F.bak-wallpalette" "$F"; exit 1; }
o=$(tr -cd '{' < "$F" | wc -c); c=$(tr -cd '}' < "$F" | wc -c)
[ "$o" = "$c" ] || { echo "braces unbalanced, restoring"; cp "$F.bak-wallpalette" "$F"; exit 1; }
echo "done. Undo: cp $F.bak-wallpalette $F"
exec "$HOME/.local/bin/viii" restart
