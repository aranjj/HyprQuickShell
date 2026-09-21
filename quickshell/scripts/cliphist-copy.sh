#!/usr/bin/env bash
# Quickshell Clipboard Copy Helper
# Intelligently decodes and copies clipboard items with correct Wayland MIME types.

id="$1"
mode="${2:-auto}" # auto | image | file | text

if [ -z "$id" ]; then
    echo "Usage: $0 <cliphist_id> [mode]" >&2
    exit 1
fi

raw=$(printf '%s\t' "$id" | cliphist decode)

# 1. Check if raw data is direct binary image data from cliphist
if printf '%s\t' "$id" | cliphist decode | file -b --mime-type - 2>/dev/null | grep -q "^image/"; then
    mime=$(printf '%s\t' "$id" | cliphist decode | file -b --mime-type - 2>/dev/null)
    [ -z "$mime" ] && mime="image/png"
    printf '%s\t' "$id" | cliphist decode | wl-copy --type "$mime"
    exit 0
fi

# 2. Check if raw content is a local file URI or path
trimmed=$(echo "$raw" | head -n 1 | tr -d '\r\n')
file_path=""

if [[ "$trimmed" =~ ^file:// ]]; then
    # Decode URL (e.g., file:///home/aran/pasted%20file.png -> /home/aran/pasted file.png)
    file_path=$(python3 -c "import urllib.parse, sys; print(urllib.parse.unquote(sys.argv[1][7:]))" "$trimmed" 2>/dev/null)
elif [[ "$trimmed" =~ ^/ ]] && [ -e "$trimmed" ]; then
    file_path="$trimmed"
fi

# If mode is explicitly "text", copy the raw text/path
if [ "$mode" = "text" ]; then
    printf '%s\t' "$id" | cliphist decode | wl-copy --type text/plain
    exit 0
fi

# If it's a valid existing local file on disk
if [ -n "$file_path" ] && [ -e "$file_path" ]; then
    mime=$(file -b --mime-type "$file_path" 2>/dev/null)

    # If it is an image file and mode is auto or image
    if [[ "$mime" =~ ^image/ ]] && [ "$mode" != "file" ]; then
        # Copy raw image bytes so apps (Discord, Telegram, Browser, GIMP, etc.) receive the actual PNG/image
        wl-copy --type "$mime" < "$file_path"
        exit 0
    else
        # For non-image files or explicit "file" mode, copy as text/uri-list so file managers (Dolphin) paste the file
        encoded_path=$(python3 -c "import urllib.parse, sys; print('file://' + urllib.parse.quote(sys.argv[1]))" "$file_path" 2>/dev/null)
        printf "%s\r\n" "$encoded_path" | wl-copy --type text/uri-list
        exit 0
    fi
fi

# 3. Fallback: plain text / code snippet
printf '%s\t' "$id" | cliphist decode | wl-copy
