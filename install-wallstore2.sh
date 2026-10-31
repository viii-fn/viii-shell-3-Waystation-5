#!/usr/bin/env bash
# install-wallstore2.sh: Wallstore v2 (hub opens on Wallstore, full wallpaper bg, page animations, load/error states)
# Backup: ~/viii-shell-3/.bak-wallstore2/. Rolls back on any failure. NO_RESTART=1 skips the shell restart.
set -u
P="$HOME/viii-shell-3"
[ -d "$P/quickshell/hub" ] || { echo "no $P/quickshell/hub"; exit 1; }
command -v perl >/dev/null || { echo "perl missing"; exit 1; }
perl "$P/apply-wallstore2.pl" || exit 1
echo "done. Undo: cp -r $P/.bak-wallstore2/. $P/quickshell/"
[ -n "${NO_RESTART:-}" ] || exec "$HOME/.local/bin/viii" restart
