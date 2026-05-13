#!/usr/bin/env bash
#
# List files in Google Drive
#
# Usage:
#   ./list_files.sh [OPTIONS]
#
# Options:
#   --folder-id ID     List files within a specific folder (default: root)
#   --shared-with-me   List only files shared with you (not owned by you)
#   --since N          Only files modified in the last N days
#   --limit N          Max number of files to return (default: 50)
#   --type TYPE        Filter by MIME type: doc, sheet, slide, folder, or full MIME string
#   --human            Human-readable output (default: JSON)
#
# Examples:
#   ./list_files.sh
#   ./list_files.sh --shared-with-me
#   ./list_files.sh --folder-id 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs
#   ./list_files.sh --type doc --limit 20
#   ./list_files.sh --human

set -euo pipefail

# ============================================================================
# DEFAULTS
# ============================================================================

FOLDER_ID="root"
LIMIT=50
TYPE_FILTER=""
SINCE_DAYS=""
SHARED_WITH_ME=false
HUMAN=false

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --folder-id)
            [[ $# -ge 2 ]] || { echo "ERROR: --folder-id requires an argument" >&2; exit 1; }
            FOLDER_ID="$2"
            shift 2
            ;;
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
        --since)
            [[ $# -ge 2 ]] || { echo "ERROR: --since requires an argument" >&2; exit 1; }
            [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]] || { echo "ERROR: --since requires a positive integer" >&2; exit 1; }
            SINCE_DAYS="$2"
            shift 2
            ;;
        --shared-with-me)
            SHARED_WITH_ME=true
            shift
            ;;
        --human)
            HUMAN=true
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $(basename "$0") [--folder-id ID] [--limit N] [--type TYPE] [--human]" >&2
            exit 1
            ;;
    esac
done

# ============================================================================
# BUILD QUERY
# ============================================================================

# Map friendly type names to Drive MIME types
resolve_mime_type() {
    case "$1" in
        doc)   echo "application/vnd.google-apps.document" ;;
        sheet) echo "application/vnd.google-apps.spreadsheet" ;;
        slide) echo "application/vnd.google-apps.presentation" ;;
        folder) echo "application/vnd.google-apps.folder" ;;
        *)     echo "$1" ;;
    esac
}

build_params() {
    local parts=()
    parts+=("trashed = false")

    if [ "$SHARED_WITH_ME" = true ]; then
        parts+=("sharedWithMe = true")
    fi

    if [ -n "$TYPE_FILTER" ]; then
        local mime
        mime=$(resolve_mime_type "$TYPE_FILTER")
        parts+=("mimeType = \"${mime}\"")
    fi

    if [ -n "$SINCE_DAYS" ]; then
        local since_date
        since_date=$(date -u -d "${SINCE_DAYS} days ago" +"%Y-%m-%dT%H:%M:%S")
        parts+=("modifiedTime > '${since_date}'")
    fi

    local base_query=""
    for part in "${parts[@]}"; do
        if [ -n "$base_query" ]; then
            base_query="$base_query and $part"
        else
            base_query="$part"
        fi
    done

    # Use jq --arg to safely interpolate FOLDER_ID into the Drive query
    jq -n \
        --arg q      "$base_query" \
        --arg folder "$FOLDER_ID" \
        --argjson ps "$LIMIT" \
        --arg fields "files(id,name,mimeType,modifiedTime,size,parents,webViewLink)" \
        '{
            q:        ($q + (if $folder != "" then (" and \"" + $folder + "\" in parents") else "" end)),
            pageSize: $ps,
            fields:   $fields,
            orderBy:  "modifiedTime desc"
        }'
}

# ============================================================================
# MAIN
# ============================================================================

PARAMS=$(build_params)

echo "Listing Drive files..." >&2

RAW_OUTPUT=$(gws drive files list --params "$PARAMS")

if [ "$HUMAN" = true ]; then
    echo "=== Google Drive Files ==="
    if command -v jq >/dev/null 2>&1; then
        echo "$RAW_OUTPUT" | jq -r '.files[] | "\(.name)\t[\(.mimeType | split(".") | last)]\t\(.modifiedTime)\t\(.id)"' \
            | column -t -s $'\t'
    else
        echo "$RAW_OUTPUT"
    fi
else
    if command -v jq >/dev/null 2>&1; then
        echo "$RAW_OUTPUT" | jq '{
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
