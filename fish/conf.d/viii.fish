# ~/.config/fish/conf.d/viii.fish
# Just the custom aliases and commands from the old zsh setup, plus dotnet.

# dotnet: DOTNET_ROOT and PATH (-g = this session only, -a = append, same as zsh's PATH=$PATH:...)
set -gx DOTNET_ROOT $HOME/.dotnet
fish_add_path -g -a $HOME/.dotnet $HOME/.dotnet/tools

status is-interactive; or return

alias rebar='killall waybar; setsid waybar >/dev/null 2>&1 & disown'
alias rebind='micro ~/.config/hypr/hyprland.lua'
alias clean='~/.local/bin/clean.sh'
alias clean-cache='~/.local/bin/clean-caches'
alias vt2='~/.local/bin/viii-theme'
alias deepclean='~/.local/bin/deepclean'

# dotfiles bare repo: use `dot` instead of `git` for dotfiles
alias dot='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
alias dotlg='lazygit --git-dir=$HOME/.dotfiles --work-tree=$HOME'

# yazi wrapper: after you quit yazi, the shell cd's into the folder you ended in
function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    command yazi $argv --cwd-file="$tmp"
    if read -z cwd < "$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end
