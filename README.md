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

## Keybinds

These are the defaults from `hypr/hyprland/keybinds.lua`; the `kb*` names it uses are set in
`hypr/variables.lua`. Actions written as `shell:*` are Hyprland global shortcuts answered by whichever
shell is running — viii answers `launcher`, `settings`, `ward`, `shot`, `briUp` and `briDown`.

### Shell and session

| Key | Action |
| --- | --- |
| `SUPER + Return` | Open the hub (`shell:launcher`) |
| `SUPER + I` | Settings (`shell:settings`) |
| `SUPER + N` | Notification history (`shell:ward`) |
| `SUPER + P` | `shell:pact` |
| `SUPER + A` | `shell:quick` (glyph quick settings) |
| `SUPER + SHIFT + W` | `shell:wall` (glyph wallpapers) |
| `CTRL + ALT + Delete` | Power menu (`shell:power`) |
| `SUPER + Escape` | Power menu (`shell:power`) |
| `SUPER + L` | Lock (`hyprlock`) |
| `SUPER + ALT + L` | Re-lock while locked (`hyprlock`) |
| `SUPER + SHIFT + L` | Suspend (then hibernate) |

### Brightness, volume and media

| Key | Action |
| --- | --- |
| `XF86MonBrightnessUp` / `Down` | Brightness up / down (`shell:briUp` / `briDown`) |
| `XF86AudioRaiseVolume` / `LowerVolume` | Volume +5% / −5% (unmutes) |
| `XF86AudioMute` | Mute output |
| `SUPER + SHIFT + M` | Mute output |
| `XF86AudioMicMute` | Mute microphone |
| `CTRL + SUPER + Space`, `XF86AudioPlay`, `XF86AudioPause` | Play / pause |
| `CTRL + SUPER + Equal`, `XF86AudioNext` | Next track |
| `CTRL + SUPER + Minus`, `XF86AudioPrev` | Previous track |
| `XF86AudioStop` | Stop |

### Workspaces

| Key | Action |
| --- | --- |
| `SUPER + 1…0` | Focus workspace 1…10 |
| `SUPER + ALT + 1…0` | Move window to workspace 1…10 |
| `CTRL + SUPER + 1…0` | Focus the matching workspace in another group |
| `CTRL + SUPER + ALT + 1…0` | Move window to the matching workspace in another group |
| `SUPER + Page_Up` / `Page_Down` | Previous / next workspace |
| `CTRL + SUPER + Left` / `Right` | Previous / next workspace |
| `SUPER + mouse_down` / `mouse_up` | Previous / next workspace (scroll wheel) |
| `CTRL + SUPER + mouse_down` / `mouse_up` | Previous / next workspace group |

### Moving windows between workspaces

| Key | Action |
| --- | --- |
| `SUPER + ALT + Page_Up` / `Page_Down` | Move window to previous / next workspace |
| `SUPER + ALT + mouse_down` / `mouse_up` | Move window to previous / next workspace |
| `CTRL + SUPER + SHIFT + Left` / `Right` | Move window to previous / next workspace |
| `CTRL + SUPER + SHIFT + Up` | Move window to the special workspace |
| `CTRL + SUPER + SHIFT + Down` | Move window out of the special workspace |
| `SUPER + ALT + S` | Move window to the special workspace |

### Window groups

| Key | Action |
| --- | --- |
| `ALT + Tab` | Cycle to the next window in the group |
| `SHIFT + ALT + Tab` | Cycle to the previous window in the group |
| `CTRL + ALT + Tab` | Next group |
| `CTRL + SHIFT + ALT + Tab` | Previous group |
| `SUPER + Comma` | Toggle grouping |
| `SUPER + U` | Remove the window from its group |
| `SUPER + SHIFT + Comma` | Lock the group |

### Window actions

| Key | Action |
| --- | --- |
| `SUPER + Left` / `Right` / `Up` / `Down` | Focus in that direction |
| `SUPER + SHIFT + Left` / `Right` / `Up` / `Down` | Move window in that direction |
| `SUPER + Minus` / `Equal` | Shrink / grow width |
| `SUPER + SHIFT + Minus` / `Equal` | Shrink / grow height |
| `SUPER + ALT + Left` / `Right` / `Up` / `Down` | Resize in that direction |
| `SUPER + SHIFT + mouse:272` | Drag window |
| `SUPER + Z` | Drag window |
| `SUPER + mouse:272` | Resize window |
| `SUPER + X` | Resize window |
| `SUPER + J` | Toggle split (dwindle) |
| `CTRL + SUPER + Backslash` | Centre window |
| `CTRL + SUPER + ALT + Backslash` | Resize to 55% × 70% and centre |
| `SUPER + ALT + Backslash` | Picture-in-picture |
| `SUPER + SHIFT + P` | Pin window |
| `SUPER + F` | Fullscreen |
| `SUPER + ALT + F` | Maximised (bordered fullscreen) |
| `SUPER + ALT + Space` | Toggle floating |
| `SUPER + C` | Close window |

`mouse:272` is the left mouse button.

### Special workspaces

| Key | Action |
| --- | --- |
| `SUPER + S` | Toggle the special workspace |
| `CTRL + SHIFT + Escape` | Toggle the system monitor workspace (`btop`) |
| `SUPER + M` | Toggle the music workspace (`spotify-launcher`) |
| `SUPER + D` | Toggle the communication workspace (`Telegram`) |
| `SUPER + R` | Toggle the todo workspace |

### Apps and utilities

| Key | Action |
| --- | --- |
| `SUPER + Q` | Terminal (`kitty -1`) |
| `SUPER + W` | Browser (`firefox`) |
| `SUPER + E` | File manager (`thunar`) |
| `SUPER + SHIFT + K` | Editor (unset by default) |
| `CTRL + ALT + V` | Audio settings (`pavucontrol`) |
| `Print`, `SUPER + SHIFT + S` | Screenshot (`shell:shot`) |
| `SUPER + ALT + R` | Record monitor with sound |
| `CTRL + ALT + R` | Record monitor without sound |
| `SUPER + SHIFT + ALT + R` | Record a region without sound |
| `SUPER + SHIFT + C` | Pick a colour (`hyprpicker -a`) |
| `SUPER + SHIFT + U` | Kill a window (`hyprctl kill`) |
| `SUPER + V` | Clipboard history (`shell:clip`) |
| `SUPER + Period` | Character picker (`shell:charms`) |
| `CTRL + SHIFT + ALT + V` | Paste the latest clipboard entry |
| `SUPER + ALT + F12` | Test notification |
| `CTRL + SUPER + SHIFT + R` | Kill the shell (`viii kill`) |
| `CTRL + SUPER + ALT + R` | Restart the shell (`viii restart`) |

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

