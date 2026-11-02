#!/usr/bin/env bash
# viii-shell-3 installer. Safe to re-run.
#
#  1. symlinks the shell and the helper scripts into ~/.config and ~/.local/bin
#  2. first run only: copies your current Hyprland config (symlinks resolved) into ~/viii-shell-3/hypr/,
#     patches the glyph parts to use viii, and makes ~/.config/hypr symlinks into that folder
#  3. your old ~/.config/hypr is MOVED aside (never deleted) and put back automatically
#     if Hyprland reports a config error or loses keybinds after the switch
set -euo pipefail
proj="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ts="$(date +%s)"
hypr="$HOME/.config/hypr"

link() { # link <source> <target>
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -e "$dst" && ! -L "$dst" ]]; then mv "$dst" "$dst.bak.$ts"; echo "backed up existing $dst"; fi
    ln -sfn "$src" "$dst"
    echo "linked  $dst -> $src"
}

chmod +x "$proj/bin/"* "$proj/install.sh"
mkdir -p "$HOME/.local/state/viii" "$HOME/.cache/viii/palettes"
: > "$HOME/.cache/viii/hypr-lua.log"

link "$proj/quickshell"       "$HOME/.config/quickshell/viii"
link "$proj/bin/viii"         "$HOME/.local/bin/viii"
link "$proj/bin/viii-palette" "$HOME/.local/bin/viii-palette"
link "$proj/bin/viii-theme"   "$HOME/.local/bin/viii-theme"
link "$proj/bin/viii-weather" "$HOME/.local/bin/viii-weather"
link "$proj/bin/viii-about"   "$HOME/.local/bin/viii-about"

missing=()
for c in quickshell matugen resvg magick hyprctl brightnessctl nmcli hyprlock; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
((${#missing[@]})) && echo "WARNING: missing commands: ${missing[*]}"

# ---------------------------------------------------------------- Hyprland
installed=0
[[ "$(readlink -f "$hypr/hyprland.lua" 2>/dev/null || true)" == "$proj/hypr/hyprland.lua" ]] && installed=1

if [[ $installed -eq 0 ]]; then
    src="$(readlink -f "$hypr")"
    for f in variables.lua scheme/demonshot.lua hyprland/functions.lua hyprland/keybinds.lua hyprland/rules.lua; do
        [[ -f "$src/$f" ]] || { echo "Expected $src/$f but it is missing. Nothing was changed."; exit 1; }
    done

    # keep ONLY keybinds and window rules (plus the 3 files they need: variables, functions, scheme).
    # Everything else in your old config (env, input, general, decoration, animations, execs, ...) is dropped.
    # cp -L follows symlinks, so the project owns real files.
    mkdir -p "$proj/hypr/hyprland" "$proj/hypr/scheme"
    cp -L "$src/variables.lua" "$proj/hypr/variables.lua"
    cp -L "$src/scheme/demonshot.lua" "$proj/hypr/scheme/demonshot.lua"
    for n in functions keybinds rules; do
        cp -L "$src/hyprland/$n.lua" "$proj/hypr/hyprland/$n.lua"
    done

    # point glyph's pieces at viii:
    #   "rice" (the shell switcher) becomes the viii script, so the start/restart/kill binds drive viii
    sed -i 's#home \.\. "/\.config/quickshell/rice/rice"#home .. "/.local/bin/viii"#' "$proj/hypr/variables.lua"
    #   lock screen: plain hyprlock
    sed -i 's#rice \.\. " lock"#"hyprlock"#' "$proj/hypr/variables.lua"
    #   SUPER+Space was glyph's "altar"; it is the PS button now
    sed -i '/kbAltar/d' "$proj/hypr/hyprland/keybinds.lua"
    #   glyph / demonshot layer rules and the Rice switcher window rule
    sed -i -e '/title = "Rice"/d' -e '/namespace = "demonshot-/d' -e '/namespace = "glyph-/d' "$proj/hypr/hyprland/rules.lua"

    # sanity check before touching anything live: exactly one bind (the altar) must be gone
    old_binds="$(grep -c 'hl\.bind' "$src/hyprland/keybinds.lua" || true)"
    new_binds="$(grep -c 'hl\.bind' "$proj/hypr/hyprland/keybinds.lua" || true)"
    if [[ "$new_binds" -ne $((old_binds - 1)) ]]; then
        echo "Bind count check failed (old $old_binds, new $new_binds). Nothing was changed in ~/.config/hypr."
        exit 1
    fi

    before="$(hyprctl binds 2>/dev/null | grep -c 'key:' || true)"

    # swap: old config moved aside, new folder of symlinks into the project
    bk="$HOME/.config/hypr.glyph-backup-$ts"
    mv "$hypr" "$bk"
    mkdir -p "$hypr"
    for f in "$proj"/hypr/*; do ln -sfn "$f" "$hypr/$(basename "$f")"; done
    echo "old Hyprland config moved to $bk"

    hyprctl reload >/dev/null 2>&1 || true
    sleep 2
    errs="$(hyprctl configerrors 2>&1 | tr -d '[:space:]' || true)"
    after="$(hyprctl binds 2>/dev/null | grep -c 'key:' || true)"

    if [[ -n "$errs" || "$after" -lt "$before" ]]; then
        echo
        echo "PROBLEM after the switch (binds before: $before, after: $after). Restoring your old config."
        hyprctl configerrors 2>&1 || true
        rm -rf "$hypr"
        mv "$bk" "$hypr"
        hyprctl reload >/dev/null 2>&1 || true
        echo "Restored. Copy the errors above and send them to Claude."
        exit 1
    fi
    echo "Hyprland switched. Keybinds before: $before, after: $after."
    echo
    echo "Lines that still mention glyph in your new config (comments are fine):"
    grep -rn -i glyph "$proj/hypr" || echo "  none"
    echo
    echo "To undo the Hyprland change at any time:"
    echo "  rm -rf ~/.config/hypr; mv $bk ~/.config/hypr; hyprctl reload"
else
    echo "Hyprland config already points at the project; left alone."
fi

# glyph is not part of this setup any more
qs kill -c glyph 2>/dev/null || true

echo
echo "Starting viii..."
exec "$proj/bin/viii" restart
