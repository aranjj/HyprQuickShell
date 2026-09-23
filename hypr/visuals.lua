--------------------------------------------------------------------------------
-- LOOK & FEEL, ANIMATIONS, LAYOUTS & RULES
-- See https://wiki.hypr.land/Configuring/Basics/Variables/
--------------------------------------------------------------------------------

-- Dynamic borders from Matugen (fallback to default if not yet generated)
local active_border = { colors = {"rgba(33ccffee)", "rgba(00ff99ee)"}, angle = 45 }
local inactive_border = "rgba(595959aa)"

package.loaded["colors"] = nil
local ok, matugen_colors = pcall(require, "colors")
if ok and type(matugen_colors) == "table" and matugen_colors.active_border then
    active_border = matugen_colors.active_border
    if matugen_colors.inactive_border then
        inactive_border = matugen_colors.inactive_border
    end
end

hl.config({
    general = {
        gaps_in          = 10,
        gaps_out         = 15,
        border_size      = 2,

        col = {
            active_border   = active_border,
            inactive_border = inactive_border,
        },

        -- Resize windows by dragging borders/gaps
        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding         = 10,
        rounding_power   = 5,

        active_opacity   = 0.97,
        inactive_opacity = 0.95,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled   = true,
            size      = 6,
            passes    = 2,
            vibrancy  = 0.420,
        },
    },

    animations = {
        enabled = true,
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        background_color        = "rgba(000000ff)",
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    scrolling = {
        fullscreen_on_one_column = true,
    },
})

-- ── Bézier Curves & Springs ──────────────────────────────────────────────────
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

-- ── Animation Tree ───────────────────────────────────────────────────────────
hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "slide" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "slide" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

-- ── Workspace Rules ──────────────────────────────────────────────────────────
-- Persistent workspaces 1-5
for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true })
end

-- ── Window Rules ─────────────────────────────────────────────────────────────
hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name       = "fix-xwayland-drags",
    match      = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus   = true,
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move  = "20 monitor_h-120",
    float = true,
})

-- ── Quickshell Frosted Glass Layer Blur Rules ─────────────────────────────────
local quickshell_layers = {
    "quickshell-bar",
    "quickshell-apple-menu",
    "quickshell-control-center",
    "quickshell-dynamic-island",
    "quickshell-calendar",
    "quickshell-spotlight",
    "quickshell-clipboard",
    "quickshell-power-menu",
    "quickshell-notification-popups",
    "quickshell-about-dialog",
    "quickshell-wallpaper-picker",
    "quickshell-osd",
    "quickshell-screenshot-toolbar",
    "quickshell-screenshot-preview",
    "quickshell-emojis",
    "quickshell-polkit",
}

for _, ns in ipairs(quickshell_layers) do
    hl.layer_rule({
        match        = { namespace = ns },
        blur         = true,
        ignore_alpha = 0.2,
    })
end
