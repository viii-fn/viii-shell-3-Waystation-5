#!/usr/bin/env bash
# install-look.sh: borders, rounding, shadow, blur + the demo's animations. Touches only hypr/hyprland.lua,
# hypr/viii.lua and adds hypr/hyprland/look.lua (never install.sh). Backup: ~/viii-shell-3/.bak-look/
# NO_RELOAD=1 skips the hyprctl reload.
set -u
P="$HOME/viii-shell-3"
[ -f "$P/hypr/hyprland.lua" ] && [ -f "$P/hypr/viii.lua" ] || { echo "missing $P/hypr/hyprland.lua or viii.lua"; exit 1; }
command -v perl >/dev/null || { echo "perl missing"; exit 1; }
perl "$P/apply-look.pl" || exit 1
[ -e "$HOME/.config/hypr/hyprland/look.lua" ] || echo "WARNING: ~/.config/hypr/hyprland/look.lua not visible (is ~/.config/hypr/hyprland a symlink to the project?)"
echo "undo: cp $P/.bak-look/hypr/hyprland.lua $P/hypr/hyprland.lua; cp $P/.bak-look/hypr/viii.lua $P/hypr/viii.lua; rm $P/hypr/hyprland/look.lua"
[ -n "${NO_RELOAD:-}" ] && exit 0
hyprctl reload >/dev/null 2>&1
sleep 1
echo "== configerrors"; hyprctl configerrors 2>&1
echo "== lua log"; cat "$HOME/.cache/viii/hypr-lua.log" 2>/dev/null || echo "(empty)"
