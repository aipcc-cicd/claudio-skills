#!/usr/bin/env bash
#
# Read/export the content of a Google Drive document
#
# Usage:
#   ./read_document.sh <file-id> [OPTIONS]
#
# Options:
#   --format FORMAT    Export format: text (default), html
#   --human            Human-readable output (default: JSON with content embedded)
#
# Supported source types:
#   Google Docs        -> exported as plain text or HTML
#   Google Sheets      -> exported as CSV
#   Google Slides      -> exported as plain text
#   Plain text/code    -> downloaded directly
#
# Examples:
#   ./read_document.sh 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74NxxH4
#   ./read_document.sh 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74NxxH4 --format html
#   ./read_document.sh 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74NxxH4 --human

set -euo pipefail

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

if [[ $# -lt 1 ]]; then
    echo "ERROR: Missing required argument: file-id" >&2
    echo "Usage: $(basename "$0") <file-id> [--format text|html] [--human]" >&2
    exit 1
fi

FILE_ID="$1"
shift

FORMAT="text"
HUMAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --format)
            [[ $# -ge 2 ]] || { echo "ERROR: --format requires an argument" >&2; exit 1; }
            FORMAT="$2"
            shift 2
            ;;
        --human)
            HUMAN=true
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $(basename "$0") <file-id> [--format text|html] [--human]" >&2
            exit 1
            ;;
    esac
done

# Validate format
case "$FORMAT" in
    text|html) ;;
    *) echo "ERROR: Unsupported format '$FORMAT'. Valid options: text, html" >&2; exit 1 ;;
esac

# jq is required for metadata parsing
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed. Install via: ../../../tools/jq/install.sh" >&2
    exit 1
fi

# ============================================================================
# HELPERS
# ============================================================================

# Map source MIME type + format to export MIME type
resolve_export_mime() {
    local source_mime="$1"
    local format="$2"

    case "$source_mime" in
        application/vnd.google-apps.document)
            case "$format" in
                html)     echo "text/html" ;;
                markdown) echo "text/plain" ;;  # gws exports as plain; markdown conversion is post-processing
                *)        echo "text/plain" ;;
            esac
            ;;
        application/vnd.google-apps.spreadsheet)
            echo "text/csv"
            ;;
        application/vnd.google-apps.presentation)
            echo "text/plain"
            ;;
        *)
            echo ""  # Non-Google-native files use alt=media download
            ;;
    esac
}

is_google_native() {
    local mime="$1"
    [[ "$mime" == application/vnd.google-apps.* ]] && \
    [[ "$mime" != application/vnd.google-apps.folder ]]
}

# ============================================================================
# MAIN
# ============================================================================

echo "Fetching metadata for file: $FILE_ID" >&2

METADATA=$(gws drive files get \
    --params "$(jq -n --arg id "$FILE_ID" \
        '{fileId: $id, fields: "id,name,mimeType,modifiedTime,size,webViewLink"}')")

FILE_NAME=$(echo "$METADATA" | jq -r '.name // "unknown"')
FILE_MIME=$(echo "$METADATA" | jq -r '.mimeType // ""')
MODIFIED=$(echo "$METADATA" | jq -r '.modifiedTime // ""')
WEB_LINK=$(echo "$METADATA" | jq -r '.webViewLink // ""')

echo "Reading: $FILE_NAME ($FILE_MIME)" >&2

if [[ "$FILE_MIME" = "application/vnd.google-apps.folder" ]]; then
    echo "ERROR: Cannot read a folder. Use list_files.sh --folder-id to list its contents." >&2
    exit 1
fi

EXPORT_MIME=$(resolve_export_mime "$FILE_MIME" "$FORMAT")
TMP_FILE=$(mktemp ./gws-doc-XXXXXX)
trap 'rm -f "$TMP_FILE"' EXIT

if is_google_native "$FILE_MIME"; then
    # Export Google-native document
    gws drive files export \
        --params "$(jq -n --arg id "$FILE_ID" --arg mime "$EXPORT_MIME" \
            '{fileId: $id, mimeType: $mime}')" \
        -o "$TMP_FILE" >/dev/null
else
    # Download binary/text file directly
    gws drive files get \
        --params "$(jq -n --arg id "$FILE_ID" '{fileId: $id, alt: "media"}')" \
        -o "$TMP_FILE" >/dev/null
fi

CONTENT=$(cat "$TMP_FILE")

if [ "$HUMAN" = true ]; then
    echo "=== $FILE_NAME ==="
    echo "ID: $FILE_ID"
    echo "Type: $FILE_MIME"
    echo "Modified: $MODIFIED"
    echo "Link: $WEB_LINK"
    echo ""
    echo "--- Content ---"
    echo "$CONTENT"
else
    jq -n \
        --arg id "$FILE_ID" \
        --arg name "$FILE_NAME" \
        --arg mime "$FILE_MIME" \
        --arg modified "$MODIFIED" \
        --arg link "$WEB_LINK" \
        --arg format "$FORMAT" \
        --arg content "$CONTENT" \
        '{
            id: $id,
            name: $name,
            mimeType: $mime,
            modifiedTime: $modified,
            webViewLink: $link,
            exportFormat: $format,
            content: $content
        }'
fi
