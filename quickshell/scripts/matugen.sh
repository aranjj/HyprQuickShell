#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# OMARCHY-STYLE UNIFIED DESKTOP THEME GENERATOR
# Wallpaper → Matugen → colors.toml (Source of Truth)
# Synchronizes: Quickshell, KDE/Qt, GTK 3/4, Hyprland, and Kitty
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

HOME_DIR="${HOME:-/home/$USER}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
WP_FILE="$CONFIG_DIR/quickshell/wallpaper.txt"
SAVED_DIR_FILE="$CONFIG_DIR/quickshell/wallpaper_dir.txt"
CONFIG_FILE="$CONFIG_DIR/matugen/config.toml"
THEME_TOML="$CONFIG_DIR/theme/colors.toml"
QS_THEME_DIR="$CONFIG_DIR/quickshell/theme"
COLORS_JSON="$QS_THEME_DIR/colors.json"
HYPR_COLORS_LUA="$CONFIG_DIR/hypr/colors.lua"

IMG="${1:-}"

# Helper to validate that an image path exists and is a readable file
is_valid_image() {
    local f="${1#file://}"
    [ -n "$f" ] && [ -f "$f" ] && [ -s "$f" ]
}

# 1. Check if argument passed is a valid image
if is_valid_image "$IMG"; then
    IMG="${IMG#file://}"
else
    IMG=""
fi

# 2. Check saved wallpaper in wallpaper.txt if no valid argument was provided
if [ -z "$IMG" ] && [ -f "$WP_FILE" ]; then
    SAVED_WP=$(cat "$WP_FILE" 2>/dev/null | tr -d '\n' || true)
    if is_valid_image "$SAVED_WP"; then
        IMG="${SAVED_WP#file://}"
    fi
fi

# 3. If still no valid image (e.g. wallpaper missing on this system), discover wallpaper
if [ -z "$IMG" ]; then
    USER_WALL_DIR=""
    if [ -f "$SAVED_DIR_FILE" ]; then
        USER_WALL_DIR=$(cat "$SAVED_DIR_FILE" 2>/dev/null | tr -d '\n' || true)
    fi

    CANDIDATE_DIRS=(
        "$USER_WALL_DIR"
        "$HOME_DIR/Pictures/Wallpapers"
        "$HOME_DIR/Pictures"
        "$CONFIG_DIR/quickshell/wallpapers"
        "/usr/share/backgrounds"
        "/usr/share/wallpapers"
    )

    for dir in "${CANDIDATE_DIRS[@]}"; do
        if [ -n "$dir" ] && [ -d "$dir" ]; then
            FOUND=$(find "$dir" -maxdepth 2 -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) 2>/dev/null | sort | head -n 1 || true)
            if [ -n "$FOUND" ] && [ -f "$FOUND" ]; then
                IMG="$FOUND"
                # Repair wallpaper.txt with the discovered wallpaper
                mkdir -p "$CONFIG_DIR/quickshell"
                echo "file://$IMG" > "$WP_FILE" 2>/dev/null || true
                break
            fi
        fi
    done
fi

mkdir -p "$QS_THEME_DIR"

# 4. Generate color scheme via Matugen
if [ -n "$IMG" ] && [ -f "$IMG" ]; then
    matugen -c "$CONFIG_FILE" image "$IMG" --source-color-index 0

    # 4b. macOS-Style Adaptive Menu Bar Luminance Analysis (Sample top 36px)
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
else
    # Fallback when no image is found on the system at all
    echo "Notice: No wallpaper found on system. Generating fallback theme from palette..." >&2
    matugen -c "$CONFIG_FILE" color hex "#89b4fa"

    python3 -c "
import json
try:
    with open('$COLORS_JSON', 'r') as f:
        data = json.load(f)
    data['bar_is_light'] = False
    data['bar_lum'] = 0.25
    with open('$COLORS_JSON', 'w') as f:
        json.dump(data, f, indent=2)
except Exception:
    pass
" 2>/dev/null || true
fi

# 5. Maintain symlink to colors.toml in Quickshell
ln -sf "$THEME_TOML" "$QS_THEME_DIR/colors.toml"

# 6. Extract Primary & Tertiary colors
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

    # Set new AccentColor and disable accentColorFromWallpaper BEFORE applying scheme
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file kdeglobals --group General --key AccentColor "$PRIMARY_RGB" 2>/dev/null || true
        kwriteconfig6 --file kdeglobals --group General --key accentColorFromWallpaper "false" 2>/dev/null || true
        kwriteconfig6 --file kdeglobals --group General --key ColorScheme "" 2>/dev/null || true
    fi

    # Ensure colors.lua exists for Hyprland config reloads/reboots
    mkdir -p "$(dirname "$HYPR_COLORS_LUA")"
    cat <<EOF > "$HYPR_COLORS_LUA"
-- Auto-generated by Matugen. Do not edit directly.
return {
    primary = "${PRIMARY_HEX}",
    tertiary = "${TERTIARY_HEX}",
    active_border = {
        colors = {
            "rgba(${PRIMARY_STRIPPED}ee)",
            "rgba(${TERTIARY_STRIPPED}ee)"
        },
        angle = 45
    },
    inactive_border = "rgba(595959aa)",
}
EOF

    # Update Hyprland window border gradients live
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl eval "hl.config({ general = { col = { active_border = { colors = {'rgba(${PRIMARY_STRIPPED}ee)', 'rgba(${TERTIARY_STRIPPED}ee)'}, angle = 45 } } } })" >/dev/null 2>&1 || true
    fi
fi

# 7. Apply KDE / Qt Color Scheme (reads the newly updated AccentColor)
if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    plasma-apply-colorscheme Matugen >/dev/null 2>&1 || true
fi

# Notify running Dolphin instances to refresh view
if command -v qdbus6 >/dev/null 2>&1; then
    for svc in $(qdbus6 2>/dev/null | grep -E '^ org\.kde\.dolphin-' || true); do
        qdbus6 "${svc## }" /dolphin/Dolphin_1/actions/view_redisplay trigger >/dev/null 2>&1 || true
    done
fi

# 8. Generate Qt6CT Color Scheme & trigger live reload for Qt6 processes
python3 -c "
import json, os

colors_json_path = os.path.expanduser('$COLORS_JSON')
if not os.path.exists(colors_json_path):
    exit(0)

try:
    with open(colors_json_path) as f:
        c = json.load(f)

    def h(hex_str):
        return hex_str.replace('#', '').lower()

    window_text = '#ff' + h(c.get('on_surface', '#ffffff'))
    btn = '#ff' + h(c.get('surface_container_high', '#2b3035'))
    light = '#ff' + h(c.get('surface_bright', '#3c4146'))
    midlight = '#ff' + h(c.get('surface_container_highest', '#32373c'))
    dark = '#ff' + h(c.get('surface_container_low', '#1e2226'))
    mid = '#ff' + h(c.get('outline_variant', '#49454f'))
    text = '#ff' + h(c.get('on_surface', '#ffffff'))
    bright_text = '#ff' + h(c.get('on_primary', '#ffffff'))
    btn_text = '#ff' + h(c.get('on_surface', '#ffffff'))
    base = '#ff' + h(c.get('surface_dim', '#14181b'))
    window = '#ff' + h(c.get('surface', '#191d20'))
    shadow = '#ff000000'
    highlight = '#ff' + h(c.get('primary', '#80d5cf'))
    highlighted_text = '#ff' + h(c.get('on_primary', '#003735'))
    link = '#ff' + h(c.get('primary', '#80d5cf'))
    link_visited = '#ff' + h(c.get('secondary', '#b0cccb'))
    alt_base = '#ff' + h(c.get('surface_container', '#222629'))
    tooltip_base = '#ff' + h(c.get('surface_container_highest', '#32373c'))
    tooltip_text = '#ff' + h(c.get('on_surface', '#ffffff'))
    placeholder = '#ff' + h(c.get('outline', '#8e918f'))
    accent = '#ff' + h(c.get('primary', '#80d5cf'))

    palette = [
        window_text, btn, light, midlight, dark, mid, text, bright_text, btn_text,
        base, window, shadow, highlight, highlighted_text, link, link_visited,
        alt_base, tooltip_base, tooltip_text, placeholder, accent
    ]
    active_str = ', '.join(palette)
    inactive_str = active_str
    disabled_str = active_str.replace('#ff', '#80')

    out_dir = os.path.expanduser('~/.config/qt6ct/colors')
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, 'matugen.conf')

    with open(out_file, 'w') as f:
        f.write('[ColorScheme]\n')
        f.write(f'active_colors={active_str}\n')
        f.write(f'disabled_colors={disabled_str}\n')
        f.write(f'inactive_colors={inactive_str}\n')
except Exception:
    pass
" 2>/dev/null || true

# Trigger QFileSystemWatcher in Qt6CT
touch "$CONFIG_DIR/qt6ct/qt6ct.conf" 2>/dev/null || true

# 9. Reload GTK Apps via xsettingsd & gsettings
if command -v pkill >/dev/null 2>&1; then
    pkill -HUP xsettingsd 2>/dev/null || true
fi

# 10. Reload Kitty Terminal instances
if command -v pkill >/dev/null 2>&1; then
    pkill -USR1 kitty 2>/dev/null || true
fi

echo "✓ Omarchy-style theme generated and applied across Quickshell, KDE, GTK, Hyprland & Kitty for ${IMG:-fallback}"
