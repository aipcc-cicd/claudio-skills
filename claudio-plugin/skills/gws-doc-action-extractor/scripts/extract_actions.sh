#!/usr/bin/env bash
#
# Extract action items from a Google Doc (content + inline comments).
#
# Detected patterns:
#   - Lines under "Action items:" sections
#   - "create a card/ticket/jira", "open a ticket", "file a bug"
#   - "[Name] to ..." / "[Name] will ..."
#   - "TODO:", "ACTION:", "FOLLOW UP:", "FOLLOWUP:"
#   - Google Doc inline comment text ([a]..[z] blocks at end of export)
#
# Usage:
#   ./extract_actions.sh <file-id> [OPTIONS]
#
# Options:
#   --human   Human-readable output (default: JSON)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

if [[ $# -lt 1 ]]; then
    echo "ERROR: Missing required argument: file-id" >&2
    echo "Usage: $(basename "$0") <file-id> [--human]" >&2
    exit 1
fi

FILE_ID="$1"
shift

HUMAN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --human) HUMAN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

TMP_DOC=$(mktemp ./gws-action-XXXXXX)
TMP_ACTIONS=$(mktemp ./gws-actions-XXXXXX)
trap 'rm -f "$TMP_DOC" "$TMP_ACTIONS"' EXIT

fetch_and_export_google_doc "$FILE_ID" "$TMP_DOC"

# ============================================================================
# PARSING
# ============================================================================

add_action() {
    local type="$1"
    local text="$2"
    local assignee="$3"
    local linenum="$4"
    local context="$5"
    jq -n \
        --arg t  "$type" \
        --arg tx "$text" \
        --arg a  "$assignee" \
        --argjson l "$linenum" \
        --arg c  "$context" \
        '{type: $t, text: $tx, assignee: $a, line: $l, context: $c}' >> "$TMP_ACTIONS"
}

linenum=0
in_action_section=false

while IFS= read -r line; do
    linenum=$((linenum + 1))
    trimmed="${line#"${line%%[![:space:]]*}"}"   # ltrim

    # Detect start of "Action items:" section
    if echo "$trimmed" | grep -qiE '^(action|actions|action items?|next steps?)[:\s]*$'; then
        in_action_section=true
        continue
    fi

    # Detect end of action section (section divider or new date header)
    if echo "$trimmed" | grep -qE '^_{10,}|^[A-Z][a-z]+ [0-9]+,? [0-9]{4} \|'; then
        in_action_section=false
    fi

    # --- Pattern 1: lines in action items section (non-empty, non-bullet-only) ---
    if [ "$in_action_section" = true ] && [ -n "$trimmed" ] && [[ "$trimmed" != "*" ]] && [[ "$trimmed" != "-" ]]; then
        # Strip leading bullet markers
        clean="${trimmed#\* }"
        clean="${clean#- }"
        if [ -n "$clean" ]; then
            # Try to extract assignee: "[Name]" or "Name to " at start
            assignee=""
            if echo "$clean" | grep -qE '^\[.+\]'; then
                assignee=$(echo "$clean" | grep -oE '^\[.+\]' | tr -d '[]')
            elif echo "$clean" | grep -qiE '^[A-Z][a-z]+ [A-Z][a-z]+ (to |will )'; then
                assignee=$(echo "$clean" | grep -oiE '^[A-Z][a-z]+ [A-Z][a-z]+')
            fi
            add_action "action_item" "$clean" "$assignee" "$linenum" "$line"
        fi
    fi

    # --- Pattern 2: explicit "create a card/ticket/jira" anywhere ---
    if echo "$trimmed" | grep -qiE 'create a (card|ticket|jira|bug)|open a (ticket|jira|bug)|file a (bug|ticket)|open a jira'; then
        assignee=""
        if echo "$trimmed" | grep -qiE '^[A-Z][a-z]+ [A-Z][a-z]+ (to |will )'; then
            assignee=$(echo "$trimmed" | grep -oiE '^[A-Z][a-z]+ [A-Z][a-z]+')
        fi
        add_action "create_card" "$trimmed" "$assignee" "$linenum" "$line"
    fi

    # --- Pattern 3: TODO / ACTION / FOLLOW UP markers ---
    if echo "$trimmed" | grep -qiE '^(TODO|ACTION|FOLLOW\s*UP|FOLLOWUP):'; then
        clean=$(echo "$trimmed" | sed -E 's/^(TODO|ACTION|FOLLOW\s*UP|FOLLOWUP):\s*//i')
        add_action "todo" "$clean" "" "$linenum" "$line"
    fi

    # --- Pattern 4: "[Name] to ..." assignee-action pattern (outside action section) ---
    if [ "$in_action_section" = false ]; then
        if echo "$trimmed" | grep -qiE '^\[.+\] (to |will )'; then
            assignee=$(echo "$trimmed" | grep -oE '^\[.+\]' | tr -d '[]')
            clean="${trimmed#\[*\] }"
            add_action "assignee_action" "$clean" "$assignee" "$linenum" "$line"
        fi
    fi

    # --- Pattern 5: Google Doc inline comments at bottom ([a]text, [b]text, ...) ---
    if echo "$trimmed" | grep -qE '^\[[a-z]\]'; then
        comment_text=$(echo "$trimmed" | sed -E 's/^\[[a-z]\]//')
        if echo "$comment_text" | grep -qiE 'create a (card|ticket|jira|bug)|open a (ticket|jira)|action|TODO|follow.?up'; then
            add_action "doc_comment" "$comment_text" "" "$linenum" "$line"
        fi
    fi

done < "$TMP_DOC"

# Remove duplicates (same text extracted by multiple patterns)
ACTIONS_JSON=$([ -s "$TMP_ACTIONS" ] && jq -s 'unique_by(.text)' "$TMP_ACTIONS" || echo '[]')

# ============================================================================
# OUTPUT
# ============================================================================

if [ "$HUMAN" = true ]; then
    COUNT=$(echo "$ACTIONS_JSON" | jq 'length')
    echo "=== $FILE_NAME — $COUNT action(s) found ==="
    echo "$ACTIONS_JSON" | jq -r '.[] | "[\(.type)] line \(.line)\(.assignee | if . != "" then " (@\(.))" else "" end): \(.text)"'
else
    jq -n \
        --arg id   "$FILE_ID" \
        --arg name "$FILE_NAME" \
        --arg link "$WEB_LINK" \
        --argjson actions "$ACTIONS_JSON" \
        '{doc_id: $id, doc_name: $name, doc_link: $link, actions: $actions}'
fi
