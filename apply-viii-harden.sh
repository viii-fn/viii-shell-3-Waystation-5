#!/usr/bin/env bash
# apply-viii-harden.sh: replaces ~/viii-shell-3/bin/viii (backup: bin/viii.bak-harden, auto rollback)
set -u
P="$HOME/viii-shell-3"
[ -f "$P/bin/viii" ] || { echo "no $P/bin/viii"; exit 1; }
[ -f "$P/bin/viii.bak-harden" ] || cp "$P/bin/viii" "$P/bin/viii.bak-harden"
cp "$P/harden-viii/viii.new" "$P/bin/viii" && chmod +x "$P/bin/viii"
if ! bash -n "$P/bin/viii"; then
  cp "$P/bin/viii.bak-harden" "$P/bin/viii"; chmod +x "$P/bin/viii"
  echo "syntax check failed, rolled back"; exit 1
fi
echo "viii hardened. Test: viii restart && viii doctor"
