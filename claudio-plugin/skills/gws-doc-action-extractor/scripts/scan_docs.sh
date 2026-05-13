#!/usr/bin/env bash
#
# Scan Google Docs shared with you for action patterns using Drive full-text search.
#
# Usage:
#   ./scan_docs.sh [OPTIONS]
#
# Options:
#   --limit N    Max docs per pattern search (default: 20)
#   --human      Human-readable output (default: JSON)

set -euo pipefail

LIMIT=20
HUMAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --limit)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "ERROR: --limit requires a numeric value" >&2; exit 1; }
            LIMIT="$2"; shift 2 ;;
        --human) HUMAN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

search_pattern() {
    local label="$1"
    local keyword="$2"
    local q="mimeType=\"application/vnd.google-apps.document\" and trashed=false and sharedWithMe=true and fullText contains \"${keyword}\""
    local params
    params=$(jq -n --arg q "$q" --argjson n "$LIMIT" \
        '{q: $q, pageSize: $n, fields: "files(id,name,modifiedTime,webViewLink)"}')
    local raw
    raw=$(gws drive files list --params "$params")
    echo "$raw" | jq --arg label "$label" --arg kw "$keyword" \
        '{pattern: $label, keyword: $kw, total: (.files | length), files: [.files[] | {id, name, modifiedTime, webViewLink}]}'
}

echo "Scanning shared docs for action patterns..." >&2

# Run all pattern searches
RESULTS=$(jq -s '.' <(
    search_pattern "create_card"  "create a card"
    search_pattern "create_ticket" "create a ticket"
    search_pattern "action_item"  "action item"
    search_pattern "open_ticket"  "open a ticket"
    search_pattern "create_jira"  "create a jira"
    search_pattern "file_bug"     "file a bug"
))

# Deduplicate docs across all patterns, aggregate matched pattern types per doc
MERGED=$(echo "$RESULTS" | jq '
    [.[] | .pattern as $p | .files[] | {id, name, modifiedTime, webViewLink, pattern: $p}]
    | group_by(.id)
    | map({
        id:           .[0].id,
        name:         .[0].name,
        modifiedTime: .[0].modifiedTime,
        webViewLink:  .[0].webViewLink,
        patterns:     [.[].pattern]
      })
    | sort_by(.modifiedTime) | reverse
    | {total: length, docs: .}
')

if [ "$HUMAN" = true ]; then
    echo "=== Docs with action patterns ==="
    echo "$MERGED" | jq -r '.docs[] | "\(.name)  patterns=[\(.patterns | join(","))]\n  \(.webViewLink)"'
else
    echo "$MERGED"
fi
