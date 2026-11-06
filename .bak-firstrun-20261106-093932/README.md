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
