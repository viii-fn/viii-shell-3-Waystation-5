#!/usr/bin/env bash
# install-hyprcolors.sh: Hyprland border colours from the wallpaper palette (matugen). Never touches install.sh.
# Backup: ~/viii-shell-3/.bak-hyprcolors/. NO_THEME=1 skips the first viii-theme run.
set -u
P="$HOME/viii-shell-3"
for f in matugen/config.toml bin/viii-theme hypr/hyprland.lua; do [ -f "$P/$f" ] || { echo "missing $P/$f"; exit 1; }; done
command -v perl >/dev/null || { echo "perl missing"; exit 1; }
perl "$P/apply-hyprcolors.pl" || exit 1
if ! bash -n "$P/bin/viii-theme"; then
  cp "$P/.bak-hyprcolors/bin_viii-theme" "$P/bin/viii-theme"; echo "syntax check failed, rolled back viii-theme"; exit 1
fi
echo "undo: cp $P/.bak-hyprcolors/matugen_config.toml $P/matugen/config.toml; cp $P/.bak-hyprcolors/bin_viii-theme $P/bin/viii-theme; cp $P/.bak-hyprcolors/hypr_hyprland.lua $P/hypr/hyprland.lua"
[ -n "${NO_THEME:-}" ] && exit 0
bash "$P/bin/viii-theme" 2>&1
echo "== colours"; cat "$HOME/.cache/viii/hypr-colors.lua" 2>/dev/null || echo "(not generated)"
