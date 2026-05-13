#!/usr/bin/env bash
#
# Search for files in Google Drive
#
# Usage:
#   ./search_files.sh <query> [OPTIONS]
#
# Options:
#   --limit N          Max number of results (default: 20)
#   --type TYPE        Filter by type: doc, sheet, slide, folder, or full MIME string
#   --human            Human-readable output (default: JSON)
#
# The query supports Google Drive search syntax:
#   name contains 'report'       -> files with "report" in the name
#   fullText contains 'budget'   -> files containing the word "budget"
#   name = 'Q1 Report'           -> exact name match
#
# Examples:
#   ./search_files.sh "quarterly report"
#   ./search_files.sh "budget" --type sheet
#   ./search_files.sh "release notes" --limit 5 --human

set -euo pipefail

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

if [[ $# -lt 1 ]]; then
    echo "ERROR: Missing required argument: query" >&2
    echo "Usage: $(basename "$0") <query> [--limit N] [--type TYPE] [--human]" >&2
    exit 1
fi

QUERY_TERM="$1"
shift

LIMIT=20
TYPE_FILTER=""
HUMAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --limit)
            [[ $# -ge 2 ]] || { echo "ERROR: --limit requires an argument" >&2; exit 1; }
            [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]] || { echo "ERROR: --limit requires a positive integer" >&2; exit 1; }
            LIMIT="$2"
            shift 2
            ;;
        --type)
            [[ $# -ge 2 ]] || { echo "ERROR: --type requires an argument" >&2; exit 1; }
            TYPE_FILTER="$2"
            shift 2
            ;;
        --human)
            HUMAN=true
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $(basename "$0") <query> [--limit N] [--type TYPE] [--human]" >&2
            exit 1
            ;;
    esac
done

# ============================================================================
# BUILD QUERY
# ============================================================================

resolve_mime_type() {
    case "$1" in
        doc)    echo "application/vnd.google-apps.document" ;;
        sheet)  echo "application/vnd.google-apps.spreadsheet" ;;
        slide)  echo "application/vnd.google-apps.presentation" ;;
        folder) echo "application/vnd.google-apps.folder" ;;
        *)      echo "$1" ;;
    esac
}

# ============================================================================
# MAIN
# ============================================================================

MIME_FILTER=""
if [ -n "$TYPE_FILTER" ]; then
    MIME_FILTER=$(resolve_mime_type "$TYPE_FILTER")
fi

# Escape double quotes in the search term so they don't break the Drive q string
SAFE_QUERY_TERM="${QUERY_TERM//\"/\\\"}"

# Use jq --arg to safely interpolate user input into the Drive query
PARAMS=$(jq -n \
    --arg qt   "$SAFE_QUERY_TERM" \
    --argjson n "$LIMIT" \
    --arg mime  "$MIME_FILTER" \
    '{
        q: (
            "trashed = false and (name contains \"" + $qt + "\" or fullText contains \"" + $qt + "\")" +
            (if $mime != "" then (" and mimeType = \"" + $mime + "\"") else "" end)
        ),
        pageSize: $n,
        fields:   "files(id,name,mimeType,modifiedTime,size,parents,webViewLink)",
        orderBy:  "modifiedTime desc"
    }')

echo "Searching Drive for: $QUERY_TERM" >&2

RAW_OUTPUT=$(gws drive files list --params "$PARAMS")

RESULT_COUNT=$(echo "$RAW_OUTPUT" | jq '.files | length' 2>/dev/null || echo "?")
echo "Found $RESULT_COUNT result(s)" >&2

if [ "$HUMAN" = true ]; then
    echo ""
    echo "=== Search Results: \"$QUERY_TERM\" ==="
    if command -v jq >/dev/null 2>&1; then
        echo "$RAW_OUTPUT" | jq -r \
            '.files[] | "\(.name)\t[\(.mimeType | split(".") | last)]\t\(.modifiedTime | split("T")[0])\t\(.id)"' \
            | column -t -s $'\t'
    else
        echo "$RAW_OUTPUT"
    fi
else
    if command -v jq >/dev/null 2>&1; then
        echo "$RAW_OUTPUT" | jq \
            --arg q "$QUERY_TERM" \
            '{
                query: $q,
                total: (.files | length),
                files: [.files[] | {
                    id,
                    name,
                    type: (.mimeType | split(".") | last),
                    mimeType,
                    modifiedTime,
                    size: (.size // "N/A"),
                    webViewLink
                }]
            }'
    else
        echo "$RAW_OUTPUT"
    fi
fi
