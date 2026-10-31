function tshot --wraps='grim ~/shot.png; and wl-copy < ~/shot.png' --description 'alias tshot=grim ~/shot.png; and wl-copy < ~/shot.png'
    grim ~/shot.png; and wl-copy < ~/shot.png $argv
end
