#!/usr/bin/env bash
# viii-shell-3 installer. Symlinks only, safe to re-run.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() { # link <source> <target>
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        mv "$dst" "$dst.bak.$(date +%s)"
        echo "backed up existing $dst"
    fi
    ln -sfn "$src" "$dst"
    echo "linked  $dst -> $src"
}

chmod +x "$root/bin/"* "$root/install.sh"

link "$root/quickshell"        "$HOME/.config/quickshell/viii"
link "$root/hypr/viii.lua"     "$HOME/.config/hypr/viii.lua"
link "$root/bin/viii-palette"  "$HOME/.local/bin/viii-palette"
link "$root/bin/viii"          "$HOME/.local/bin/viii"

mkdir -p "$HOME/.local/state/viii" "$HOME/.cache/viii/palettes"

missing=()
for c in quickshell matugen resvg magick hyprctl brightnessctl; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
((${#missing[@]})) && echo "WARNING: missing commands: ${missing[*]}"

if ! grep -qs 'require("viii")' "$HOME/.config/hypr/hyprland.lua"; then
    echo
    echo "One manual step: add this line at the END of ~/.config/hypr/hyprland.lua"
    echo '    require("viii")'
fi

echo
echo "Done. Start it with:  viii start      (go back to glyph with: viii glyph)"
