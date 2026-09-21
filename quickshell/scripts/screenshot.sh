#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# QuickShell Screenshot Helper — Freeze-Frame Enabled
# Captures display state at the exact moment of invocation.
# Supports frozen mode (crops from instant freeze snapshot)
# and direct keybinding mode (freezes at T=0 before slurp).
# ─────────────────────────────────────────────────────────

MODE="${1:-region}"
DELAY="${2:-0}"
FREEZE_FILE="${3:-}"

SAVE_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SAVE_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="Screenshot_${TIMESTAMP}.png"
FILE="$SAVE_DIR/$FILENAME"

# Countdown delay (3s, 5s, 10s timer from toolbar if requested)
if [ "$DELAY" -gt 0 ] 2>/dev/null; then
    sleep "$DELAY"
fi

# ── Dynamic Theme Colors for Slurp ──────────────────────
RAW_HEX=$(jq -r '.primary // empty' "$HOME/.config/quickshell/theme/colors.json" 2>/dev/null)
if [ -z "$RAW_HEX" ]; then
    RAW_HEX=$(grep -m1 -E '^primary = "#' "$HOME/.config/theme/colors.toml" 2>/dev/null | cut -d'"' -f2)
fi
[ -z "$RAW_HEX" ] && RAW_HEX="#89b4fa"
HEX="${RAW_HEX#\#}"

SLURP_BORDER="#${HEX}ff"
SLURP_SELECTION="#00000000"
SLURP_BG="#00000050"
SLURP_BOX="#${HEX}25"

case "$MODE" in
    save_frozen)
        # 1:1 instantaneous full screen from toolbar freeze snapshot
        if [ -n "$FREEZE_FILE" ] && [ -f "$FREEZE_FILE" ]; then
            cp "$FREEZE_FILE" "$FILE"
        else
            grim "$FILE" || exit 0
        fi
        quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot close 2>/dev/null || true
        ;;

    region_frozen)
        # Selection on top of toolbar's frozen display
        pkill -9 -x slurp 2>/dev/null || true
        GEOM=$(slurp -d -b "$SLURP_BG" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -w 2 < /dev/null 2>/dev/null)
        if [ -z "$GEOM" ]; then
            quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot close 2>/dev/null || true
            exit 0
        fi

        X=$(echo "$GEOM" | cut -d',' -f1)
        Y=$(echo "$GEOM" | cut -d' ' -f1 | cut -d',' -f2)
        W=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f1)
        H=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f2)

        if [ -n "$FREEZE_FILE" ] && [ -f "$FREEZE_FILE" ]; then
            magick "$FREEZE_FILE" -crop "${W}x${H}+${X}+${Y}" +repage "$FILE" || grim -g "$GEOM" "$FILE" || exit 0
        else
            grim -g "$GEOM" "$FILE" || exit 0
        fi

        quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot close 2>/dev/null || true
        ;;

    window_frozen)
        # Window selection on top of toolbar's frozen display
        pkill -9 -x slurp 2>/dev/null || true
        MONITORS=$(hyprctl -j monitors 2>/dev/null)
        ACTIVE_WS=$(echo "$MONITORS" | jq -r 'map(.activeWorkspace.id) | join(",")' 2>/dev/null)
        CLIENTS=$(hyprctl -j clients 2>/dev/null)

        BOXES=$(echo "$CLIENTS" | jq -r --arg ws "$ACTIVE_WS" '
            ($ws | split(",")) as $aws |
            .[] | select(.mapped == true and .hidden == false and
                         (.workspace.id | tostring as $w | $aws | index($w)))
            | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"
        ' 2>/dev/null)

        if [ -z "$BOXES" ]; then
            BOXES=$(echo "$CLIENTS" | jq -r '.[] | select(.mapped == true and .hidden == false) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null)
        fi

        if [ -z "$BOXES" ]; then
            quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot close 2>/dev/null || true
            exit 0
        fi

        GEOM=$(echo "$BOXES" | slurp -r -d -b "$SLURP_BG" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -B "$SLURP_BOX" -w 2 2>/dev/null)
        if [ -z "$GEOM" ]; then
            quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot close 2>/dev/null || true
            exit 0
        fi

        X=$(echo "$GEOM" | cut -d',' -f1)
        Y=$(echo "$GEOM" | cut -d' ' -f1 | cut -d',' -f2)
        W=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f1)
        H=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f2)

        if [ -n "$FREEZE_FILE" ] && [ -f "$FREEZE_FILE" ]; then
            magick "$FREEZE_FILE" -crop "${W}x${H}+${X}+${Y}" +repage "$FILE" || grim -g "$GEOM" "$FILE" || exit 0
        else
            grim -g "$GEOM" "$FILE" || exit 0
        fi

        quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot close 2>/dev/null || true
        ;;

    fullscreen)
        pkill -9 -x slurp 2>/dev/null || true
        grim "$FILE" || exit 0
        ;;

    window)
        # Try visual freeze-frame overlay via Quickshell first
        if quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot snipWindow 2>/dev/null; then
            exit 0
        fi

        # Fallback to direct grim + slurp if Quickshell is not running
        pkill -9 -x slurp 2>/dev/null || true
        FREEZE_TMP="/tmp/qs_direct_$$.png"
        grim -l 1 "$FREEZE_TMP" 2>/dev/null || true

        MONITORS=$(hyprctl -j monitors 2>/dev/null)
        ACTIVE_WS=$(echo "$MONITORS" | jq -r 'map(.activeWorkspace.id) | join(",")' 2>/dev/null)
        CLIENTS=$(hyprctl -j clients 2>/dev/null)

        BOXES=$(echo "$CLIENTS" | jq -r --arg ws "$ACTIVE_WS" '
            ($ws | split(",")) as $aws |
            .[] | select(.mapped == true and .hidden == false and
                         (.workspace.id | tostring as $w | $aws | index($w)))
            | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"
        ' 2>/dev/null)

        if [ -z "$BOXES" ]; then
            BOXES=$(echo "$CLIENTS" | jq -r '.[] | select(.mapped == true and .hidden == false) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null)
        fi

        if [ -z "$BOXES" ]; then
            rm -f "$FREEZE_TMP"
            exit 0
        fi

        GEOM=$(echo "$BOXES" | slurp -r -d -b "$SLURP_BG" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -B "$SLURP_BOX" -w 2 2>/dev/null)
        if [ -z "$GEOM" ]; then
            rm -f "$FREEZE_TMP"
            exit 0
        fi

        X=$(echo "$GEOM" | cut -d',' -f1)
        Y=$(echo "$GEOM" | cut -d' ' -f1 | cut -d',' -f2)
        W=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f1)
        H=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f2)

        if [ -f "$FREEZE_TMP" ]; then
            magick "$FREEZE_TMP" -crop "${W}x${H}+${X}+${Y}" +repage "$FILE" || grim -g "$GEOM" "$FILE" || true
            rm -f "$FREEZE_TMP"
        else
            grim -g "$GEOM" "$FILE" || exit 0
        fi
        ;;

    region)
        # Try visual freeze-frame overlay via Quickshell first
        if quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot snipRegion 2>/dev/null; then
            exit 0
        fi

        # Fallback to direct grim + slurp if Quickshell is not running
        pkill -9 -x slurp 2>/dev/null || true
        FREEZE_TMP="/tmp/qs_direct_$$.png"
        grim -l 1 "$FREEZE_TMP" 2>/dev/null || true

        GEOM=$(slurp -d -b "$SLURP_BG" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -w 2 < /dev/null 2>/dev/null)
        if [ -z "$GEOM" ]; then
            rm -f "$FREEZE_TMP"
            exit 0
        fi

        X=$(echo "$GEOM" | cut -d',' -f1)
        Y=$(echo "$GEOM" | cut -d' ' -f1 | cut -d',' -f2)
        W=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f1)
        H=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f2)

        if [ -f "$FREEZE_TMP" ]; then
            magick "$FREEZE_TMP" -crop "${W}x${H}+${X}+${Y}" +repage "$FILE" || grim -g "$GEOM" "$FILE" || true
            rm -f "$FREEZE_TMP"
        else
            grim -g "$GEOM" "$FILE" || exit 0
        fi
        ;;

    *)
        echo "Unknown mode: $MODE" >&2
        exit 1
        ;;
esac

# ── Post-capture ────────────────────────────────────────
if [ -f "$FILE" ]; then
    # Shutter sound (fire-and-forget)
    canberra-gtk-play -i camera-shutter 2>/dev/null &

    # Tell Quickshell to show floating thumbnail preview
    quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot preview "$FILE" 2>/dev/null || true

    echo "$FILE"
fi
