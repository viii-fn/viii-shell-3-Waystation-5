-- viii-shell-3: the Hyprland side (loaded by hyprland.lua).
-- Every line goes through try(): if this Hyprland build rejects something, that one line is skipped
-- and logged to ~/.cache/viii/hypr-lua.log (see:  viii doctor)  instead of breaking your config.

local home = os.getenv("HOME") or ""
local log_path = home .. "/.cache/viii/hypr-lua.log"
os.execute("mkdir -p \"" .. home .. "/.cache/viii\"")

local function try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local f = io.open(log_path, "a")
        if f then f:write(label .. ": " .. tostring(err) .. "\n"); f:close() end
    end
end

---------------------------------------------------------------------------
-- Curves. Same shapes as quickshell/core/Motion.qml, so windows and shell move alike.
---------------------------------------------------------------------------
try("curve psOut",   hl.curve, "psOut",   { type = "bezier", points = { { 0.22, 1.00 }, { 0.36, 1.00 } } }) -- quick start, long soft landing
try("curve psInOut", hl.curve, "psInOut", { type = "bezier", points = { { 0.65, 0.00 }, { 0.35, 1.00 } } })
try("curve psSoft",  hl.curve, "psSoft",  { type = "bezier", points = { { 0.16, 1.00 }, { 0.30, 1.00 } } })

---------------------------------------------------------------------------
-- Window and layer animations now live in hyprland/look.lua (the demo's spring set).
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Autostart: the shell starts with Hyprland (full path: ~/.local/bin is not in Hyprland's PATH).
---------------------------------------------------------------------------
try("autostart viii", hl.on, "hyprland.start", function()
    hl.exec_cmd(home .. "/.local/bin/viii start")
end)

---------------------------------------------------------------------------
-- The shell draws its own animations, so Hyprland must not animate its layer surfaces.
---------------------------------------------------------------------------
for _, ns in ipairs({ "viii-hub", "viii-cc", "viii-osd" }) do
    try("layer no_anim " .. ns, hl.layer_rule, { match = { namespace = ns }, no_anim = true })
end

---------------------------------------------------------------------------
-- PS button. One key, bound twice: on press and on release.
-- The shell times the gap: short = tap (Control Center), long = hold (power menu, later).
-- SUPER + Space used to open glyph's "altar"; that bind is removed, so the key is free.
-- Change the key here if you want a different one.
---------------------------------------------------------------------------
local ps_key = "SUPER + Space"
try("bind ps down", hl.bind, ps_key, hl.dsp.global("shell:psDown"))
try("bind ps up",   hl.bind, ps_key, hl.dsp.global("shell:psUp"), { release = true })
