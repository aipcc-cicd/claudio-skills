#!/usr/bin/env bash
#
# Shared utilities for gws-doc-action-extractor scripts.

# Fetch Google Doc metadata and export its content as plain text.
#
# Arguments:
#   $1  FILE_ID   - Google Drive file ID
#   $2  TMP_PATH  - path to write the exported plain-text content
#
# Exports (sets in caller's scope):
#   FILE_NAME, FILE_MIME, WEB_LINK
#
# Exits with code 1 if the file is not a Google Doc.
fetch_and_export_google_doc() {
    local file_id="$1"
    local tmp_path="$2"

    echo "Fetching metadata for: $file_id" >&2

    local metadata
    metadata=$(gws drive files get \
        --params "$(jq -n --arg id "$file_id" '{fileId: $id, fields: "id,name,mimeType,modifiedTime,webViewLink"}')")

    FILE_NAME=$(echo "$metadata" | jq -r '.name // "unknown"')
    FILE_MIME=$(echo "$metadata" | jq -r '.mimeType // ""')
    WEB_LINK=$(echo "$metadata"  | jq -r '.webViewLink // ""')

    if [[ "$FILE_MIME" != "application/vnd.google-apps.document" ]]; then
        echo "ERROR: Not a Google Doc (mimeType: $FILE_MIME)" >&2
        return 1
    fi

    echo "Exporting: $FILE_NAME" >&2

    gws drive files export \
        --params "$(jq -n --arg id "$file_id" '{fileId: $id, mimeType: "text/plain"}')" \
        -o "$tmp_path" >/dev/null
}
