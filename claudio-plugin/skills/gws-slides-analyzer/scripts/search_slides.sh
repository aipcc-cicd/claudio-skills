#!/usr/bin/env bash
#
# Search for Google Slides presentations by name or full-text content.
#
# Usage:
#   ./search_slides.sh <query> [OPTIONS]
#
# Options:
#   --limit N   Maximum number of results (default: 20)
#   --human     Human-readable output (default: JSON)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "ERROR: Missing required argument: query" >&2
    echo "Usage: $(basename "$0") <query> [--limit N] [--human]" >&2
    exit 1
fi

QUERY_TEXT="$1"
shift

LIMIT=20
HUMAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --limit)
            [[ $# -gt 1 ]] || { echo "ERROR: --limit requires an argument" >&2; exit 1; }
            [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]] || { echo "ERROR: --limit requires a positive integer" >&2; exit 1; }
            LIMIT="$2"; shift 2 ;;
        --human) HUMAN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Escape backslashes then double quotes so the Drive q string is not broken
escaped_query="${QUERY_TEXT//\\/\\\\}"
escaped_query="${escaped_query//\"/\\\"}"

PARAMS=$(jq -n \
    --arg qt "$escaped_query" \
    --argjson n "$LIMIT" \
    '{
        q: ("mimeType=\"application/vnd.google-apps.presentation\" and trashed=false and (name contains \"" + $qt + "\" or fullText contains \"" + $qt + "\")"),
        pageSize: $n,
        fields: "files(id,name,modifiedTime,webViewLink)",
        orderBy: "modifiedTime desc"
    }')

echo "Searching for: $QUERY_TEXT" >&2

RAW=$(gws drive files list --params "$PARAMS")

if [ "$HUMAN" = true ]; then
    echo "=== Search: $QUERY_TEXT ==="
    echo "$RAW" | jq -r '.files[] | "\(.name)\t\(.modifiedTime)\t\(.id)"' \
        | column -t -s $'\t'
else
    echo "$RAW" | jq --arg q "$QUERY_TEXT" '{
        query: $q,
        total: (.files | length),
        files: [.files[] | {id, name, modifiedTime, webViewLink}]
    }'
fi
