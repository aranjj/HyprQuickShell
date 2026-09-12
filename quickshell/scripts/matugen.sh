#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# OMARCHY-STYLE UNIFIED DESKTOP THEME GENERATOR
# Wallpaper → Matugen → colors.toml (Source of Truth)
# Synchronizes: Quickshell, KDE/Qt, GTK 3/4, Hyprland, and Kitty
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

IMG="${1:-}"

# Fallback to saved wallpaper if argument is empty
if [ -z "$IMG" ]; then
    if [ -f "/home/aran/.config/quickshell/wallpaper.txt" ]; then
        IMG=$(cat /home/aran/.config/quickshell/wallpaper.txt | tr -d '\n')
    else
        IMG="/home/aran/Pictures/Wallpapers/blueeve.jpg"
    fi
fi

# Clean file:// URI scheme
IMG="${IMG#file://}"

if [ ! -f "$IMG" ]; then
    echo "Wallpaper file not found: $IMG" >&2
    exit 1
fi

CONFIG_FILE="/home/aran/.config/matugen/config.toml"

# 1. Run Matugen to generate all configured templates
matugen -c "$CONFIG_FILE" image "$IMG" --source-color-index 0

THEME_TOML="/home/aran/.config/theme/colors.toml"
QS_THEME_DIR="/home/aran/.config/quickshell/theme"
mkdir -p "$QS_THEME_DIR"

# 2. Maintain symlink to colors.toml in Quickshell
ln -sf "$THEME_TOML" "$QS_THEME_DIR/colors.toml"

COLORS_JSON="$QS_THEME_DIR/colors.json"

# 2b. macOS-Style Adaptive Menu Bar Luminance Analysis (Sample top 36px)
python3 -c "
import json
from PIL import Image

try:
    with Image.open('$IMG') as im:
        im = im.convert('RGB')
        w, h = im.size
        sample_h = max(36, int(h * 0.04))
        crop = im.crop((0, 0, w, sample_h)).resize((100, 10))
        b = crop.tobytes()
        total_lum = sum(0.2126 * b[i] + 0.7152 * b[i+1] + 0.0722 * b[i+2] for i in range(0, len(b), 3))
        avg_lum = total_lum / (len(b) / 3) / 255.0
        is_light = avg_lum > 0.55

        with open('$COLORS_JSON', 'r') as f:
            data = json.load(f)

        data['bar_is_light'] = is_light
        data['bar_lum'] = round(avg_lum, 3)

        with open('$COLORS_JSON', 'w') as f:
            json.dump(data, f, indent=2)
except Exception:
    pass
" 2>/dev/null || true

# 3. Apply KDE / Qt Color Scheme & Accent Color
if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    plasma-apply-colorscheme Matugen >/dev/null 2>&1 || true
fi

if [ -f "$COLORS_JSON" ] && command -v jq >/dev/null 2>&1; then
    PRIMARY_HEX=$(jq -r '.primary' "$COLORS_JSON")
    PRIMARY_STRIPPED="${PRIMARY_HEX#'#'}"
    TERTIARY_HEX=$(jq -r '.tertiary' "$COLORS_JSON")
    TERTIARY_STRIPPED="${TERTIARY_HEX#'#'}"

    # Extract RGB components for KDE kdeglobals
    R=$((16#${PRIMARY_STRIPPED:0:2}))
    G=$((16#${PRIMARY_STRIPPED:2:2}))
    B=$((16#${PRIMARY_STRIPPED:4:2}))
    PRIMARY_RGB="$R,$G,$B"

    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file kdeglobals --group General --key AccentColor "$PRIMARY_RGB" 2>/dev/null || true
    fi

    # 4. Update Hyprland window border gradients live
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl repl "hl.config({ general = { col = { active_border = { colors = {'rgba(${PRIMARY_STRIPPED}ee)', 'rgba(${TERTIARY_STRIPPED}ee)'}, angle = 45 } } } })" >/dev/null 2>&1 || true
    fi
fi

# 5. Reload GTK Apps via xsettingsd & gsettings
if command -v pkill >/dev/null 2>&1; then
    pkill -HUP xsettingsd 2>/dev/null || true
fi

# 6. Reload Kitty Terminal instances
if command -v pkill >/dev/null 2>&1; then
    pkill -USR1 kitty 2>/dev/null || true
fi

echo "✓ Omarchy-style theme generated and applied across Quickshell, KDE, GTK, Hyprland & Kitty for $IMG"
