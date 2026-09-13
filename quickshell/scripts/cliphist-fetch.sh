#!/usr/bin/env bash
THUMB_DIR="/tmp/quickshell_clip_thumbs"
mkdir -p "$THUMB_DIR"

raw=$(cliphist list)
[ -z "$raw" ] && exit 0

TAB=$'\t'
while IFS="$TAB" read -r id preview; do
    [ -z "$id" ] && continue
    if [[ "$preview" =~ ^\[\[\ binary\ data ]]; then
        thumb="${THUMB_DIR}/${id}.png"
        if [ ! -s "$thumb" ]; then
            printf "%s\t" "$id" | cliphist decode > "$thumb" 2>/dev/null &
        fi
    fi
done <<< "$raw"
wait

printf "%s\n" "$raw"
