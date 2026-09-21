#!/usr/bin/env bash
# Quickshell Clipboard Watcher & Dynamic Island OSD feedback
# Captures copy events, updates cliphist, and sends visual HUD notification to Dynamic Island.

TYPE="${1:-text}" # "text" or "image"

if [ "$TYPE" = "image" ]; then
    TMP_IMG=$(mktemp /tmp/qs_clip_XXXXXX.png)
    cat > "$TMP_IMG"

    # Store in cliphist
    cliphist store < "$TMP_IMG"

    # Check if file has content
    if [ -s "$TMP_IMG" ]; then
        DIMS=$(identify -format "%wx%h" "$TMP_IMG" 2>/dev/null)
        if [ -n "$DIMS" ]; then
            DIMS=$(echo "$DIMS" | sed 's/x/ × /')
        else
            DIMS="PNG Image"
        fi
        quickshell ipc -p /home/aran/.config/quickshell/shell.qml call island copyFeedback "image" "Image copied" "$DIMS" 2>/dev/null || true
    fi
    rm -f "$TMP_IMG"

elif [ "$TYPE" = "text" ]; then
    TMP_TXT=$(mktemp /tmp/qs_clip_XXXXXX.txt)
    cat > "$TMP_TXT"

    # Store in cliphist
    cliphist store < "$TMP_TXT"

    RAW=$(cat "$TMP_TXT")
    rm -f "$TMP_TXT"

    [ -z "$RAW" ] && exit 0

    # Check if raw data is file URLs (from Dolphin or file manager)
    if [[ "$RAW" =~ ^file:// ]]; then
        FILE_COUNT=$(echo "$RAW" | grep -c "^file://")
        if [ "$FILE_COUNT" -gt 1 ]; then
            quickshell ipc -p /home/aran/.config/quickshell/shell.qml call island copyFeedback "file" "Copied" "$FILE_COUNT files" 2>/dev/null || true
        else
            FIRST_URI=$(echo "$RAW" | head -n1 | tr -d '\r\n')
            FILE_PATH=$(python3 -c "import urllib.parse, sys; print(urllib.parse.unquote(sys.argv[1][7:]))" "$FIRST_URI" 2>/dev/null)
            FILENAME=$(basename "$FILE_PATH" 2>/dev/null)
            [ -z "$FILENAME" ] && FILENAME="1 file"

            if [[ "$FILENAME" =~ \.(png|jpe?g|webp|gif|bmp|svg)$ ]] && [ -f "$FILE_PATH" ]; then
                DIMS=$(identify -format "%wx%h" "$FILE_PATH" 2>/dev/null)
                if [ -n "$DIMS" ]; then
                    DIMS=$(echo "$DIMS" | sed 's/x/ × /')
                    quickshell ipc -p /home/aran/.config/quickshell/shell.qml call island copyFeedback "image" "Image copied" "$DIMS" 2>/dev/null || true
                    exit 0
                fi
                quickshell ipc -p /home/aran/.config/quickshell/shell.qml call island copyFeedback "image" "Image copied" "$FILENAME" 2>/dev/null || true
            else
                quickshell ipc -p /home/aran/.config/quickshell/shell.qml call island copyFeedback "file" "Copied" "$FILENAME" 2>/dev/null || true
            fi
        fi
    else
        # Regular plain text
        CLEAN=$(echo "$RAW" | tr '\n\r' '  ' | sed -E 's/[[:space:]]+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ ${#CLEAN} -gt 32 ]; then
            PREVIEW="${CLEAN:0:30}…"
        else
            PREVIEW="$CLEAN"
        fi

        quickshell ipc -p /home/aran/.config/quickshell/shell.qml call island copyFeedback "text" "Copied" "$PREVIEW" 2>/dev/null || true
    fi
fi
