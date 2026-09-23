--------------------------------------------------------------------------------
-- HYPRLAND MAIN CONFIGURATION
--------------------------------------------------------------------------------

-- Ensure ~/.config/hypr/ is in Lua package path
local hypr_dir = os.getenv("HOME") .. "/.config/hypr/"
package.path = hypr_dir .. "?.lua;" .. package.path

-- ── Environment Variables ────────────────────────────────────────────────────
hl.env("QT_QPA_PLATFORMTHEME", "kde")  --replace kde with qt6ct to use qt6 settings for theming
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- ── Default User Programs ────────────────────────────────────────────────────
-- (Preserved for Quickshell SystemService.qml app integration)
local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "hyprlauncher"
local browser     = "firefox"
local editor      = "code"

-- ── Load Modular Configurations ──────────────────────────────────────────────
require("monitors")
require("autostart")
require("inputs")
require("visuals")
require("keybindings")
