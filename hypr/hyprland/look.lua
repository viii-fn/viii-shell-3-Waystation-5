-- viii-shell-3: look and feel. File: ~/viii-shell-3/hypr/hyprland/look.lua (loaded by hyprland.lua).
-- Borders, rounding, gaps, shadow, blur and the window/layer/workspace animations, taken from the demo config.
-- Every block goes through try(): if this Hyprland build rejects one, only that block is skipped and
-- logged to ~/.cache/viii/hypr-lua.log (see:  viii doctor).

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
-- Border colours. Defaults are the demo's gradient. When viii-theme starts writing
-- ~/.cache/viii/hypr-colors.lua (returns { active = {colors, angle}, inactive = "rgba(...)" })
-- it overrides these automatically. A missing file is fine.
---------------------------------------------------------------------------
local active   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }
local inactive = "rgba(595959aa)"
local okc, c = pcall(dofile, home .. "/.cache/viii/hypr-colors.lua")
if okc and type(c) == "table" then
    active   = c.active   or active
    inactive = c.inactive or inactive
end

---------------------------------------------------------------------------
-- Look: gaps, 2px border, rounded corners, soft shadow, light blur (the GPU is weak: 1 pass).
---------------------------------------------------------------------------
try("general", hl.config, {
    general = {
        gaps_in     = 5,
        gaps_out    = 20,
        border_size = 2,
        col = { active_border = active, inactive_border = inactive },
        resize_on_border = false,
        allow_tearing    = false,
    },
})

try("decoration", hl.config, {
    decoration = {
        rounding         = 15,
        rounding_power   = 2,
        active_opacity   = 1,
        inactive_opacity = 1,
        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },
        blur = {
            enabled  = true,
            size     = 4,
            passes   = 3,
            vibrancy = 0,
        },
    },
})

---------------------------------------------------------------------------
-- Animations: the demo's set (springs for windows, fades, layers, vertical workspaces).
---------------------------------------------------------------------------
try("animations on", hl.config, { animations = { enabled = true } })

try("curve easeOutQuint",   hl.curve, "easeOutQuint",   { type = "bezier", points = { { 0.23, 1 },    { 0.32, 1 } } })
try("curve easeInOutCubic", hl.curve, "easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
try("curve linear",         hl.curve, "linear",         { type = "bezier", points = { { 0, 0 },       { 1, 1 } } })
try("curve almostLinear",   hl.curve, "almostLinear",   { type = "bezier", points = { { 0.5, 0.5 },   { 0.75, 1 } } })
try("curve quick",          hl.curve, "quick",          { type = "bezier", points = { { 0.15, 0 },    { 0.1, 1 } } })
try("curve easy",           hl.curve, "easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

local anims = {
    { leaf = "global",        enabled = true, speed = 10,   bezier = "default" },
    { leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" },
    { leaf = "windows",       enabled = true, speed = 4.79, spring = "easy" },
    { leaf = "windowsIn",     enabled = true, speed = 4.1,  spring = "easy", style = "popin 87%" },
    { leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" },
    { leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" },
    { leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" },
    { leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" },
    { leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" },
    { leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" },
    { leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear", style = "fade" },
    { leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" },
    { leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" },
    { leaf = "workspaces",    enabled = true, speed = 4,    bezier = "easeOutQuint", style = "slidevert" },
    { leaf = "workspacesIn",  enabled = true, speed = 4,    bezier = "easeOutQuint", style = "slidevert" },
    { leaf = "workspacesOut", enabled = true, speed = 4,    bezier = "easeOutQuint", style = "slidevert" },
    { leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" },
}
for _, a in ipairs(anims) do try("anim " .. a.leaf, hl.animation, a) end
