# viii-shell-3

A PlayStation 5 style home screen for Hyprland, built on Quickshell + matugen.

```
./install.sh      # symlinks into ~/.config and ~/.local/bin
viii start        # stops glyph, starts viii
viii log          # shell log
viii glyph        # back to the old shell
```

Layout: `quickshell/` (the shell), `hypr/viii.lua` (curves, window animations, PS button), `bin/` (helpers).

Phase 1: core, hub (home row, library grid, launch zoom, screen time, matugen tinting).
Next: PS button tap (control center) and hold (power menu), settings, search, sounds, lock screen.

## First-run setup (Waystation)

The first time the shell starts, a one-time setup runs in its own Quickshell instance (`quickshell/setup/`, started
by `viii start` while `~/.local/state/viii/setup-done` does not exist). It never runs again once it has finished.

1. Keyboard: `keyboard.svg` with the Super key ringed; press Super (or Enter) to continue.
2. Language: the keyboard layout list (same as Settings > System > Language), applied through `viii-kb`.
3. Display: read-only resolution and HDR support (`viii-display`).
4. User agreement: Waystation / viii-shell-3.
5. System software: `viii-deps` installs the dependencies (Arch, Fedora, Debian-based), then offers an optional full update.

```
viii setup status | run | reset | skip     # show, rerun, rerun on next start, or mark as done
viii log setup                             # the setup instance's log
cat ~/.cache/viii/setup-start.log          # why the setup did or did not start (and any QML errors)
Ctrl+Shift+Esc                             # inside the setup: leave it (marks it done)
viii-deps --info | --install --dry-run     # what the installer would do, changes nothing
```

`install.sh [--dry-run] [--no-start]` checks every target first, backs up whatever is occupied to
`~/.local/state/viii/backups/<time>/` (with a `RESTORE.sh`), then links `bin/*` into `~/.local/bin` and every other
folder into `~/.config` (`quickshell` goes to `~/.config/quickshell/viii`).

`quickshell/setup/keyboard.svg` is 640x224; its Super key is at (72,180), 46x36 (the ring in `PairScreen.qml` uses these).

