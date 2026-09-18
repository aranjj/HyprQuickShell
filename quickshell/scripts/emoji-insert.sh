#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# QuickShell Emoji Inserter
# Copies selected emoji to clipboard and pastes into active window
# ─────────────────────────────────────────────────────────

set -e

EMOJI="$1"
if [ -z "$EMOJI" ]; then
    exit 0
fi

# 1. Copy to clipboard (both CLIPBOARD and PRIMARY selection for full compatibility)
wl-copy "$EMOJI"
wl-copy --primary "$EMOJI"

# 2. Wait briefly for Quickshell overlay to unmap and focus to return to target window
sleep 0.15

# 3. Detect active window class
ACTIVE_CLASS=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty' 2>/dev/null || echo "")

# 4. Simulate paste key combination
case "$ACTIVE_CLASS" in
    [kK]itty|[aA]lacritty|[fF]oot*|[wW]ezterm*|[gG]hostty*|[kK]onsole*|*Terminal*|*terminal*|[xX]term*|[uU]rxvt*|st|st-256color)
        # Terminal applications use Ctrl+Shift+V (or Shift+Insert as fallback)
        wtype -M ctrl -M shift -s 20 -k v -s 20 -m shift -m ctrl 2>/dev/null || \
        wtype -M shift -s 20 -k Insert -s 20 -m shift 2>/dev/null
        ;;
    *)
        # General GUI applications (browsers, editors, chat) use Ctrl+V
        wtype -M ctrl -s 20 -k v -s 20 -m ctrl 2>/dev/null
        ;;
esac
