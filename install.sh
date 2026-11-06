#!/usr/bin/env bash
# viii-shell-3 (Waystation) installer. Safe to re-run.
#
#   ./install.sh [--dry-run] [--no-start]
#
#  1. VERIFY   every target is looked at first: free, already ours, or occupied. Nothing is touched yet.
#  2. BACK UP  everything that is occupied is moved to ~/.local/state/viii/backups/<timestamp>/
#              (with a RESTORE.sh that puts it all back).
#  3. LINK     everything in bin/ becomes a symlink in ~/.local/bin; every other folder or file becomes a symlink
#              in ~/.config (quickshell goes to ~/.config/quickshell/viii, the name `qs -c viii` looks for).
#  4. Hyprland is reloaded; if it reports a config error the previous ~/.config/hypr is put back.
#
# The first-run setup (keyboard, language, display, agreement, dependencies) starts by itself the first time
# the shell runs, and never again after that.
set -euo pipefail

DRY=0; START=1
for a in "$@"; do
    case "$a" in
        --dry-run)  DRY=1 ;;
        --no-start) START=0 ;;
        -h|--help)  sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown option: $a (try --help)"; exit 2 ;;
    esac
done

proj="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
binhome="$HOME/.local/bin"
state="$HOME/.local/state/viii"
ts="$(date +%Y%m%d-%H%M%S)"
backup="$state/backups/$ts"

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ the plan: SRC<TAB>DST
srcs=(); dsts=()
add() { srcs+=("$1"); dsts+=("$2"); }

shopt -s nullglob
for f in "$proj"/bin/*; do
    [[ -f "$f" ]] && add "$f" "$binhome/$(basename "$f")"
done
for f in "$proj"/*; do
    n="$(basename "$f")"
    case "$n" in
        bin|install.sh|README*|LICENSE*|*.md|*.bak*) continue ;;   # not config
    esac
    if [[ "$n" == quickshell ]]; then add "$f" "$cfg/quickshell/viii"; else add "$f" "$cfg/$n"; fi
done
shopt -u nullglob

((${#srcs[@]})) || die "nothing to install: $proj/bin and the config folders are missing"
[[ "$proj" == "$HOME/viii-shell-3" ]] || warn "the project is in $proj, but bin/viii-theme expects ~/viii-shell-3. Move it there (or edit P= in bin/viii-theme)."

# ------------------------------------------------------------------ 1. verify
# status: ours (already links to the project) | free | occupied
status_of() {
    local src="$1" dst="$2"
    if [[ -L "$dst" ]]; then
        if [[ "$(readlink -f "$dst" 2>/dev/null || true)" == "$(readlink -f "$src")" ]]; then echo ours; else echo occupied; fi
    elif [[ -e "$dst" ]]; then echo occupied
    else echo free; fi
}

st=(); occupied=0
say "Checking ${#srcs[@]} targets..."
for i in "${!srcs[@]}"; do
    src="${srcs[$i]}"; dst="${dsts[$i]}"
    [[ -e "$src" ]] || die "missing in the project: $src"
    # the target's parent folder must not itself lead back into the project (a symlinked ~/.config/quickshell, say)
    pd="$(readlink -f "$(dirname "$dst")" 2>/dev/null || true)"
    case "$pd/" in "$(readlink -f "$src")"/*) die "$(dirname "$dst") leads into $src. Fix that by hand first." ;; esac
    s="$(status_of "$src" "$dst")"
    st+=("$s")
    [[ "$s" == occupied ]] && occupied=$((occupied + 1))
    printf '  %-9s %s\n' "$s" "$dst"
done
say "$occupied occupied, $(printf '%s\n' "${st[@]}" | grep -c '^ours$') already linked, $(printf '%s\n' "${st[@]}" | grep -c '^free$') free."

if (( DRY )); then say "Dry run: nothing was changed."; exit 0; fi

# ------------------------------------------------------------------ 2. back up everything occupied
moved=()   # "dst<TAB>backup path", for the rollback and RESTORE.sh
undo() {
    local m
    for m in ${moved[@]+"${moved[@]}"}; do
        d="${m%%$'\t'*}"; b="${m#*$'\t'}"
        rm -rf "$d" 2>/dev/null || true
        mv "$b" "$d" 2>/dev/null || true
    done
}
if (( occupied > 0 )); then
    trap 'warn "failed: putting everything back"; undo' ERR
    mkdir -p "$backup"
    say "Backing up to $backup"
    for i in "${!srcs[@]}"; do
        [[ "${st[$i]}" == occupied ]] || continue
        dst="${dsts[$i]}"
        rel="${dst#$HOME/}"; [[ "$rel" == "$dst" ]] && rel="abs${dst}"
        mkdir -p "$backup/$(dirname "$rel")"
        mv "$dst" "$backup/$rel"
        moved+=("$dst"$'\t'"$backup/$rel")
        say "  backed up $dst"
    done
    {
        echo '#!/usr/bin/env bash'
        echo "# Puts back what install.sh of $ts replaced."
        echo 'set -e'
        for m in "${moved[@]}"; do
            d="${m%%$'\t'*}"; b="${m#*$'\t'}"
            printf 'rm -rf %q; mv %q %q\n' "$d" "$b" "$d"
        done
        echo 'echo restored'
    } > "$backup/RESTORE.sh"
    chmod +x "$backup/RESTORE.sh"
fi

# ------------------------------------------------------------------ 3. link
chmod +x "$proj"/bin/* "$proj/install.sh" 2>/dev/null || true
mkdir -p "$state" "$HOME/.cache/viii/palettes"
: > "$HOME/.cache/viii/hypr-lua.log"
for i in "${!srcs[@]}"; do
    src="${srcs[$i]}"; dst="${dsts[$i]}"
    if [[ "${st[$i]}" == ours ]]; then say "  kept    $dst"; continue; fi
    mkdir -p "$(dirname "$dst")"
    ln -sfn "$src" "$dst"
    say "  linked  $dst -> $src"
done
trap - ERR

case ":$PATH:" in *":$binhome:"*) ;; *) warn "$binhome is not in your PATH (Hyprland starts the shell with the full path, so that part still works)." ;; esac

missing=()
for c in quickshell matugen resvg magick hyprctl brightnessctl nmcli hyprlock; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
((${#missing[@]})) && say "Not installed yet: ${missing[*]}  (the first-run setup offers to install them)"

# ------------------------------------------------------------------ 4. Hyprland: reload, and put the old config back on an error
hypr="$cfg/hypr"
hypr_bk=""
for m in ${moved[@]+"${moved[@]}"}; do [[ "${m%%$'\t'*}" == "$hypr" ]] && hypr_bk="${m#*$'\t'}"; done
if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
    sleep 2
    errs="$(hyprctl configerrors 2>&1 | tr -d '[:space:]' || true)"
    if [[ -n "$errs" ]]; then
        echo; hyprctl configerrors 2>&1 || true
        if [[ -n "$hypr_bk" ]]; then
            warn "Hyprland reports config errors. Putting your previous ~/.config/hypr back."
            rm -rf "$hypr"; mv "$hypr_bk" "$hypr"
            hyprctl reload >/dev/null 2>&1 || true
            say "Restored. Send the errors above to Claude."
            exit 1
        fi
        warn "Hyprland reports config errors (see above); there was no previous config to restore."
    else
        say "Hyprland reloaded without errors."
    fi
fi

((occupied > 0)) && say "To undo everything this run replaced: bash $backup/RESTORE.sh"

# ------------------------------------------------------------------ start
if (( START )) && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    say; say "Starting viii..."
    "$proj/bin/viii" restart
else
    say; say "Done. Start it from your Hyprland session with: viii start"
fi
say "On its first start Waystation runs its one-time setup (viii setup status / reset / skip)."
