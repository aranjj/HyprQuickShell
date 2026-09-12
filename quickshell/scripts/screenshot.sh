#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# QuickShell Screenshot Helper  —  Clean Rebuild
# Uses hyprshot for region (battle-tested interactive selection)
# Uses custom window picker (hyprshot window mode has a grim
#   race condition — screencopy fires before compositor redraws
#   after slurp unmaps, causing silent failure)
# Uses grim directly for fullscreen
# ─────────────────────────────────────────────────────────

MODE="${1:-region}"
DELAY="${2:-0}"

SAVE_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SAVE_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="Screenshot_${TIMESTAMP}.png"
FILE="$SAVE_DIR/$FILENAME"

# Countdown delay (3s, 5s, 10s timer from toolbar)
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
    fullscreen)
        pkill -9 -x slurp 2>/dev/null || true
        grim "$FILE" || exit 0
        wl-copy --type image/png < "$FILE" 2>/dev/null || true
        ;;

    window)
        # 1. Get visible window geometries on active workspaces
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
            # Fallback: all mapped windows
            BOXES=$(echo "$CLIENTS" | jq -r '.[] | select(.mapped == true and .hidden == false) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null)
        fi

        [ -z "$BOXES" ] && exit 0

        # 2. Let user click a window (slurp -r = restrict to boxes)
        GEOM=$(echo "$BOXES" | slurp -r -d -b "$SLURP_BG" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -B "$SLURP_BOX" -w 2 2>/dev/null) || exit 0
        [ -z "$GEOM" ] && exit 0

        # 3. Trim geometry to monitor bounds
        X=$(echo "$GEOM" | cut -d',' -f1)
        Y=$(echo "$GEOM" | cut -d' ' -f1 | cut -d',' -f2)
        W=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f1)
        H=$(echo "$GEOM" | cut -d' ' -f2 | cut -d'x' -f2)

        MAX_W=$(echo "$MONITORS" | jq -r '[.[] | if (.transform % 2 == 0) then (.x + .width) else (.x + .height) end] | max')
        MAX_H=$(echo "$MONITORS" | jq -r '[.[] | if (.transform % 2 == 0) then (.y + .height) else (.y + .width) end] | max')

        [ $((X + W)) -gt "$MAX_W" ] && W=$((MAX_W - X))
        [ $((Y + H)) -gt "$MAX_H" ] && H=$((MAX_H - Y))
        GEOM="${X},${Y} ${W}x${H}"

        # 4. Wait for slurp surface to fully unmap and compositor to
        #    redraw a clean frame. This is the critical fix — without
        #    this delay, grim's screencopy captures a stale frame that
        #    may include slurp's selection overlay or fail entirely.
        sleep 0.2

        # 5. Capture
        grim -g "$GEOM" "$FILE" || exit 0
        wl-copy --type image/png < "$FILE" 2>/dev/null || true
        ;;

    region)
        pkill -9 -x slurp 2>/dev/null || true
        # Interactive region selection
        GEOM=$(slurp -d -b "$SLURP_BG" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -w 2 2>/dev/null) || exit 0
        [ -z "$GEOM" ] && exit 0

        # Wait for slurp surface to fully unmap and compositor to redraw clean frame
        sleep 0.15

        # Capture region
        grim -g "$GEOM" "$FILE" || exit 0
        wl-copy --type image/png < "$FILE" 2>/dev/null || true
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
