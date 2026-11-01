#!/usr/bin/env bash
# viii-shell-3: Wallstore + palette-everywhere. Backs up every file it edits; rolls back on any failure.
# Does NOT touch ~/.config/hypr.
set -u
P="$HOME/viii-shell-3"; Q="$P/quickshell"
B="$P/.bak-wallstore"; rm -rf "$B"; mkdir -p "$B"
FILES="hub/Hub.qml hub/HomePage.qml hub/AppTile.qml hub/TopBar.qml hub/Hint.qml hub/InfoCards.qml hub/Backdrop.qml cc/CcButton.qml cc/CcContent.qml cc/ControlCenter.qml cc/Osd.qml core/Apps.qml core/Theme.qml core/qmldir shell.qml"
for f in $FILES; do [ -e "$Q/$f" ] && cp --parents "$Q/$f" "$B/" 2>/dev/null; done
restore() { echo "FAILED: $1. Restoring."; cp -a "$B$Q/." "$Q/"; rm -f "$Q/core/Wall.qml" "$Q/hub/WallstorePage.qml"; rm -rf "$Q/wall"; exit 1; }

# 1) matugen part (idempotent; the shell restart happens at the end of this script)
NO_RESTART=1 bash "$P/install-matugen.sh" || restore "matugen setup"

# 2) structural patches
perl "$P/apply-wallstore.pl" || restore "patch"

# 3) register the Wall singleton
grep -q 'Wall.qml' "$Q/core/qmldir" || printf 'singleton Wall 1.0 Wall.qml\n' >> "$Q/core/qmldir"

# 4) palette everywhere: white-alpha glass -> tinted tokens, fixed dark text/scrims -> Theme.deep
for f in hub/TopBar hub/Hint hub/InfoCards hub/Backdrop hub/HomePage cc/CcButton cc/CcContent cc/ControlCenter cc/Osd; do
  perl -0pi -e '
    s{Qt\.rgba\(1,\s*1,\s*1,\s*([0-9.]+)\)}{ my $a=$1; ($a<=0.0 ? "Qt.rgba(1, 1, 1, 0)" : $a<=0.125 ? "Theme.glass" : $a<=0.19 ? "Theme.glassHi" : $a<=0.30 ? "Theme.glassBorder" : "Theme.fg") }ge;
    s{"#0b0d12"}{Theme.deep}g; s{"#101218"}{Theme.deep}g;
    s{Qt\.rgba\(0, 0, 0, 0\.0\)}{Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.0)}g;
    s{Qt\.rgba\(0, 0, 0, 0\.55\)}{Qt.alpha(Theme.deep, 0.7)}g;
    s{Qt\.rgba\(0\.07, 0\.07, 0\.09, 0\.90\)}{Qt.alpha(Theme.deep, 0.92)}g;
  ' "$Q/$f.qml" || restore "token pass $f"
done

# 5) sanity: braces balanced everywhere we touched or added
for f in $FILES wall/WallpaperLayer.qml hub/WallstorePage.qml core/Wall.qml; do
  case "$f" in *.qml) o=$(tr -cd '{' < "$Q/$f" | wc -c); c=$(tr -cd '}' < "$Q/$f" | wc -c); [ "$o" = "$c" ] || restore "unbalanced braces in $f";; esac
done

echo "Wallstore installed. Undo: cp -a $B$Q/. $Q/ && rm -rf $Q/wall $Q/hub/WallstorePage.qml $Q/core/Wall.qml"
exec "$HOME/.local/bin/viii" restart
