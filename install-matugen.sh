#!/usr/bin/env bash
# viii-shell-3: matugen setup. Does NOT touch ~/.config/hypr.
set -u
P="$HOME/viii-shell-3"
HUB="$P/quickshell/hub/Hub.qml"
mkdir -p "$HOME/.local/bin" "$HOME/.cache/viii" "$HOME/.local/state/viii"
ln -sf "$P/bin/viii-theme" "$HOME/.local/bin/viii-theme"
chmod +x "$P/bin/viii-theme"

# Hub: when it hides, go back to the wallpaper colours
if grep -q 'Theme.applyWallpaper' "$HUB"; then echo "Hub: already patched"; else
  cp "$HUB" "$HUB.bak-matugen" || exit 1
  perl -0pi -e 's/(\} else \{\n)(\s+)(resetTimer\.restart\(\);)/$1$2Theme.applyWallpaper();\n$2$3/' "$HUB"
  grep -q 'Theme.applyWallpaper' "$HUB" || { echo "Hub patch FAILED, restoring"; cp "$HUB.bak-matugen" "$HUB"; exit 1; }
  o=$(tr -cd '{' < "$HUB" | wc -c); c=$(tr -cd '}' < "$HUB" | wc -c)
  [ "$o" = "$c" ] || { echo "Hub braces unbalanced, restoring"; cp "$HUB.bak-matugen" "$HUB"; exit 1; }
fi

# kitty: make sure it includes the generated colours (creates a minimal kitty.conf if you have none)
K="$HOME/.config/kitty/kitty.conf"
mkdir -p "$HOME/.config/kitty"
[ -e "$K" ] || : > "$K"
grep -q 'viii-colors.conf' "$K" || printf '\ninclude viii-colors.conf\n' >> "$K"

# first theme: last wallpaper, else bg.jpg, else a random one
W="$HOME/Pictures/Wallpapers"
if [ -f "$HOME/.local/state/viii/wallpaper" ]; then "$HOME/.local/bin/viii-theme" || exit 1
elif [ -f "$W/bg.jpg" ]; then "$HOME/.local/bin/viii-theme" "$W/bg.jpg" || exit 1
else "$HOME/.local/bin/viii-theme" --random || exit 1; fi

echo "== generated"; ls -l "$HOME/.cache/viii/theme.json" "$HOME/.config/kitty/viii-colors.conf" "$HOME/.config/fish/conf.d/viii-colors.fish" "$HOME/.config/gtk-4.0/gtk.css"
[ -n "${NO_RESTART:-}" ] && exit 0
exec "$HOME/.local/bin/viii" restart
