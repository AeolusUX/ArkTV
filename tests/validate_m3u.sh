#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLE_PLAYLIST="${PROJECT_ROOT}/channels/sample_playlist.m3u"
OUTPUT_JSON="$(mktemp /tmp/arktv_sample_channels.XXXXXX.json)"

cleanup() {
    [[ -f "$OUTPUT_JSON" ]] && rm -f "$OUTPUT_JSON"
}
trap cleanup EXIT

python3 "${PROJECT_ROOT}/scripts/m3u_to_json.py" "$SAMPLE_PLAYLIST" -o "$OUTPUT_JSON"

jq -e '
    type == "array" and length == 2 and
    .[0].name == "Sample News" and
    (.[0].url | startswith("https://")) and
    .[0].group == "News" and
    .[1].name == "Sample Sports" and
    .[1].group == "Sports"
' "$OUTPUT_JSON" >/dev/null

echo "Playlist M3U convertida com sucesso para JSON."

