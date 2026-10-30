-- viii-shell-3: the Hyprland side.
-- Load it from ~/.config/hypr/hyprland.lua with one line:   require("viii")
--
-- Everything is wrapped in try(): if this Hyprland build rejects a key, that single line is skipped
-- (and logged to ~/.cache/viii/hypr-lua.log) instead of breaking your whole config.

local home = os.getenv("HOME") or ""
local log_path = home .. "/.cache/viii/hypr-lua.log"

local function try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local f = io.open(log_path, "a")
        if f then
            f:write(label .. ": " .. tostring(err) .. "\n")
            f:close()
        end
    end
end

---------------------------------------------------------------------------
-- Curves. Same shapes as quickshell/core/Motion.qml, so windows and shell move alike.
---------------------------------------------------------------------------
try("curve psOut",   hl.curve, "psOut",   { type = "bezier", points = { { 0.22, 1.00 }, { 0.36, 1.00 } } }) -- quick start, long soft landing
try("curve psInOut", hl.curve, "psInOut", { type = "bezier", points = { { 0.65, 0.00 }, { 0.35, 1.00 } } })
try("curve psSoft",  hl.curve, "psSoft",  { type = "bezier", points = { { 0.16, 1.00 }, { 0.30, 1.00 } } })

---------------------------------------------------------------------------
-- Windows: an app opening slides in from the right while fading up, like a game starting.
-- (speed is in 100ms units: 5.5 = 550ms.)
-- Want it subtler? Change "slide right" to "popin 92%".
---------------------------------------------------------------------------
try("anim windowsIn",   hl.animation, { leaf = "windowsIn",   enabled = true, speed = 5.5, bezier = "psOut",   style = "slide right" })
try("anim windowsOut",  hl.animation, { leaf = "windowsOut",  enabled = true, speed = 4.0, bezier = "psInOut", style = "popin 94%" })
try("anim windowsMove", hl.animation, { leaf = "windowsMove", enabled = true, speed = 4.0, bezier = "psOut" })
try("anim fadeIn",      hl.animation, { leaf = "fadeIn",      enabled = true, speed = 5.5, bezier = "psOut" })
try("anim fadeOut",     hl.animation, { leaf = "fadeOut",     enabled = true, speed = 3.5, bezier = "psInOut" })
-- workspaces are left alone on purpose: your normal scroll stays as it is.

---------------------------------------------------------------------------
-- The hub draws its own animations, so Hyprland must not animate its layer surface.
---------------------------------------------------------------------------
try("layer rule viii-hub", hl.layer_rule, { match = { namespace = "viii-hub" }, blur = true, ignore_alpha = 0.1 })
try("layer anim viii-hub", hl.layer_rule, { match = { namespace = "viii-hub" }, no_anim = true })

---------------------------------------------------------------------------
-- PS button. One key, bound twice: on press and on release.
-- The shell times the gap: short = tap, long = hold.
-- Change the key here if SUPER + Space is already taken.
---------------------------------------------------------------------------
local ps_key = "SUPER + Space"
try("bind ps down", hl.bind, ps_key, hl.dsp.global("shell:psDown"))
try("bind ps up",   hl.bind, ps_key, hl.dsp.global("shell:psUp"), { release = true })
