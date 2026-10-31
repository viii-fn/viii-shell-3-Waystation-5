-- viii-shell-3: Hyprland config. Only window rules, keybinds, and the viii module (PS button,
-- animations, layer rules, autostart). Everything else is left at Hyprland defaults.
require("hyprland.rules")
require("hyprland.keybinds")

-- look and feel (borders, rounding, shadow, blur, animations). pcall: can never break the rest.
pcall(require, "hyprland.look")

-- pcall: a mistake in viii.lua can never break the rest. Errors go to ~/.cache/viii/hypr-lua.log
local ok, err = pcall(require, "viii")
if not ok then
    local f = io.open((os.getenv("HOME") or "") .. "/.cache/viii/hypr-lua.log", "a")
    if f then f:write("viii.lua failed to load: " .. tostring(err) .. "\n"); f:close() end
end
