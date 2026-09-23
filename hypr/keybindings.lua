--------------------------------------------------------------------------------
-- KEYBINDINGS CONFIGURATION
-- See https://wiki.hypr.land/Configuring/Basics/Binds/
--------------------------------------------------------------------------------

local mainMod = "SUPER"

-- ── Preferred Applications ───────────────────────────────────────────────────
local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "hyprlauncher"
local browser     = "firefox"
local editor      = "code"

-- ── Application Launchers ────────────────────────────────────────────────────
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd(editor))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))

-- ── Quickshell Desktop Services ──────────────────────────────────────────────
hl.bind("ALT + space",           hl.dsp.exec_cmd("quickshell ipc call launcher toggle"))
hl.bind(mainMod .. " + M",       hl.dsp.exec_cmd("quickshell ipc call powermenu open"))
hl.bind(mainMod .. " + V",       hl.dsp.exec_cmd("quickshell ipc call clipboard toggle"))
hl.bind(mainMod .. " + W",       hl.dsp.exec_cmd("quickshell ipc call wallpaper picker"))
hl.bind(mainMod .. " + ALT + W", hl.dsp.exec_cmd("quickshell ipc call wallpaper random"))
hl.bind(mainMod .. " + CTRL + E",hl.dsp.exec_cmd("quickshell ipc call emojis toggle"))
hl.bind(mainMod .. " + period",  hl.dsp.exec_cmd("quickshell ipc call emojis toggle"))
hl.bind(mainMod .. " + L",       hl.dsp.exec_cmd("quickshell ipc call lock lock"))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("quickshell ipc call nightlight toggle"))

-- ── Window Management ────────────────────────────────────────────────────────
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

-- Focus Movement (Arrow keys)
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Window Movement (Shift + Arrow keys)
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "d" }))

-- ── Workspace Navigation ─────────────────────────────────────────────────────
for i = 1, 10 do
    local key = i % 10 -- 10 maps to 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Special Workspace (Scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll Through Existing Workspaces with Mouse Wheel
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move & Resize Windows with Mouse Dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Hardware & Multimedia Keys ───────────────────────────────────────────────
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && wpctl set-mute @DEFAULT_AUDIO_SINK@ 0"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),    { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("F8",                   hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                { locked = true, repeating = true })

-- Media Playback Controls
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- ── Screenshot Keybindings ───────────────────────────────────────────────────
hl.bind("Print",                       hl.dsp.exec_cmd("/home/aran/.config/quickshell/scripts/screenshot.sh region"))
hl.bind("SHIFT + Print",               hl.dsp.exec_cmd("/home/aran/.config/quickshell/scripts/screenshot.sh fullscreen"))
hl.bind(mainMod .. " + Print",         hl.dsp.exec_cmd("/home/aran/.config/quickshell/scripts/screenshot.sh window"))
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("/home/aran/.config/quickshell/scripts/screenshot.sh region"))
hl.bind(mainMod .. " + ALT + S",       hl.dsp.exec_cmd("quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot toolbar"))
