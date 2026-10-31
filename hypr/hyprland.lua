-- viii-shell-3: Hyprland config. Only window rules, keybinds, and the viii module (PS button,
-- animations, layer rules, autostart). Everything else is left at Hyprland defaults.
require("hyprland.rules")
require("hyprland.keybinds")

-- look and feel (borders, rounding, shadow, blur, animations). pcall: can never break the rest.
package.loaded["hyprland.look"] = nil
pcall(require, "hyprland.look")

-- pcall: a mistake in viii.lua can never break the rest. Errors go to ~/.cache/viii/hypr-lua.log
local ok, err = pcall(require, "viii")
if not ok then
    local f = io.open((os.getenv("HOME") or "") .. "/.cache/viii/hypr-lua.log", "a")
    if f then f:write("viii.lua failed to load: " .. tostring(err) .. "\n"); f:close() end
end

---------------
---- CURSOR ---
---------------

hl.env("HYPRCURSOR_THEME", "default")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "default")
hl.env("XCURSOR_SIZE", "24")

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "gb",    -- was "us"
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
        },
    },
})
