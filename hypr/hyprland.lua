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
        kb_layout  = (function() local f = io.open((os.getenv("HOME") or "") .. "/.config/viii/kb_layout", "r"); if f then local v = f:read("*l"); f:close(); if v and v ~= "" then return v end end; return "gb" end)(),
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

hl.on("hyprland.start", function ()
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland XDG_SESSION_TYPE=wayland")
  hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
--  hl.exec_cmd("hyprlock")
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
--  hl.exec_cmd("dms run >/dev/null 2>&1 & disown")
end)
