#!/usr/bin/env bash
#
# Extract action items from content added in the last N days in a Google Doc.
#
# Identifies date-labeled sections (e.g. "Apr 27, 2026"), filters to those
# within the last N days, and extracts action patterns from only that content.
# Output includes full surrounding context for rich Jira card descriptions.
#
# Usage:
#   ./extract_recent_actions.sh <file-id> [OPTIONS]
#
# Options:
#   --days N     Look back N days (default: 7)
#   --human      Human-readable output (default: JSON)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

if [[ $# -lt 1 ]]; then
    echo "ERROR: Missing required argument: file-id" >&2
    echo "Usage: $(basename "$0") <file-id> [--days N] [--human]" >&2
    exit 1
fi

FILE_ID="$1"
shift

DAYS=7
HUMAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --days)
            [[ $# -gt 1 ]] || { echo "ERROR: --days requires a value" >&2; exit 1; }
            [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]] || { echo "ERROR: --days requires a positive integer" >&2; exit 1; }
            DAYS="$2"; shift 2 ;;
        --human) HUMAN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ============================================================================
# FETCH METADATA + EXPORT
# ============================================================================

TMP_DOC=$(mktemp ./gws-recent-XXXXXX)
TMP_ACTIONS=$(mktemp ./gws-actions-XXXXXX)
trap 'rm -f "$TMP_DOC" "$TMP_ACTIONS"' EXIT

fetch_and_export_google_doc "$FILE_ID" "$TMP_DOC"

# ============================================================================
# DATE SECTION PARSING
# ============================================================================

CUTOFF_EPOCH=$(date -u -d "${DAYS} days ago" +%s)
TODAY_EPOCH=$(date -u +%s)

# Returns epoch for a date string like "Apr 27, 2026" or empty if not a date
parse_date_header() {
    local line="$1"
    # Match patterns: "Apr 27, 2026" / "April 27, 2026" / "Apr 27 2026"
    if echo "$line" | grep -qiE '^\s*(Jan(uary)?|Feb(ruary)?|Mar(ch)?|Apr(il)?|May|Jun(e)?|Jul(y)?|Aug(ust)?|Sep(tember)?|Oct(ober)?|Nov(ember)?|Dec(ember)?)\s+[0-9]{1,2},?\s+20[0-9]{2}\s*$'; then
        local cleaned
        cleaned=$(echo "$line" | sed 's/,//g' | xargs)
        date -d "$cleaned" +%s 2>/dev/null || true
    fi
}

# ============================================================================
# EXTRACT SECTIONS WITHIN DATE RANGE
# ============================================================================

# Build array of (epoch, section_date_str, content_lines) for matching sections
# We process the file in two passes:
#   Pass 1: identify date-header line numbers and their epochs
#   Pass 2: extract content for in-range sections

declare -a SECTION_EPOCHS=()
declare -a SECTION_DATES=()
declare -a SECTION_STARTS=()   # line numbers where section content begins
declare -a SECTION_ENDS=()     # line numbers where section ends (exclusive)

linenum=0
while IFS= read -r line; do
    line="${line%$'\r'}"   # strip Windows carriage return
    linenum=$((linenum + 1))
    epoch=$(parse_date_header "$line")
    if [ -n "$epoch" ]; then
        SECTION_EPOCHS+=("$epoch")
        SECTION_DATES+=("$(echo "$line" | xargs)")
        SECTION_STARTS+=("$((linenum + 1))")
        # Close previous section
        n=${#SECTION_ENDS[@]}
        if [ "$n" -gt 0 ] && [ "${SECTION_ENDS[n-1]}" = "0" ]; then
            SECTION_ENDS[n-1]="$linenum"
        fi
        SECTION_ENDS+=("0")  # 0 = not yet closed
    fi
done < "$TMP_DOC"

# Close the last section
n=${#SECTION_ENDS[@]}
if [ "$n" -gt 0 ]; then
    SECTION_ENDS[n-1]="$((linenum + 1))"
fi

# ============================================================================
# ACTION PATTERN MATCHING ON IN-RANGE SECTIONS
# ============================================================================

add_action() {
    local section_date="$1"
    local type="$2"
    local text="$3"
    local assignee="$4"
    local linenum="$5"
    local context="$6"       # surrounding lines (multi-line block)
    local description="$7"   # full Jira description

    jq -n \
        --arg sd  "$section_date" \
        --arg t   "$type" \
        --arg tx  "$text" \
        --arg a   "$assignee" \
        --argjson l "$linenum" \
        --arg c   "$context" \
        --arg d   "$description" \
        '{section_date: $sd, type: $t, text: $tx, assignee: $a, line: $l, context: $c, jira_description: $d}' >> "$TMP_ACTIONS"
}

# For each in-range section, extract lines and run patterns
for i in "${!SECTION_EPOCHS[@]}"; do
    epoch="${SECTION_EPOCHS[$i]}"
    section_date="${SECTION_DATES[$i]}"
    start="${SECTION_STARTS[$i]}"
    end="${SECTION_ENDS[$i]}"

    # Skip sections outside the date range
    if [ "$epoch" -lt "$CUTOFF_EPOCH" ] || [ "$epoch" -gt "$TODAY_EPOCH" ]; then
        continue
    fi

    echo "  Processing section: $section_date (lines $start-$end)" >&2

    # Extract section lines into a temp array
    mapfile -t SECTION_LINES < <(sed -n "${start},$((end - 1))p" "$TMP_DOC" | tr -d '\r')

    # Collect full section text for context
    SECTION_TEXT=$(printf '%s\n' "${SECTION_LINES[@]}")

    # Now scan each line for patterns
    sline=0
    for raw_line in "${SECTION_LINES[@]}"; do
        sline=$((sline + 1))
        abs_line=$((start + sline - 1))
        # Strip leading whitespace and bullet markers (* - •)
        trimmed="${raw_line#"${raw_line%%[![:space:]]*}"}"
        trimmed="${trimmed#\* }"
        trimmed="${trimmed#- }"
        trimmed="${trimmed#• }"

        # Collect context window: up to 3 lines before and after
        ctx_start=$(( sline > 3 ? sline - 3 : 0 ))
        last_index=$(( ${#SECTION_LINES[@]} - 1 ))
        ctx_end=$(( sline + 3 < last_index ? sline + 3 : last_index ))
        CONTEXT_BLOCK=$(printf '%s\n' "${SECTION_LINES[@]:$ctx_start:$((ctx_end - ctx_start + 1))}")

        # Build Jira description template
        build_description() {
            local action_text="$1"
            local assignee="$2"
            local type="$3"
            printf "Source: %s\nLink: %s\nSection date: %s\n\nPattern: %s\n%s\n\nContext:\n%s\n\nFull section:\n%s" \
                "$FILE_NAME" "$WEB_LINK" "$section_date" \
                "$type" \
                "$([ -n "$assignee" ] && echo "Mentioned assignee: $assignee" || true)" \
                "$CONTEXT_BLOCK" \
                "$SECTION_TEXT"
        }

        # --- Pattern: explicit create a card/ticket/jira ---
        if echo "$trimmed" | grep -qiE 'create a (card|ticket|jira|bug)|open a (ticket|jira|bug)|file a (bug|ticket)'; then
            assignee=""
            if echo "$trimmed" | grep -qiE '^\[.+\]'; then
                assignee=$(echo "$trimmed" | grep -oE '^\[.+\]' | tr -d '[]')
            fi
            desc=$(build_description "$trimmed" "$assignee" "create_card")
            add_action "$section_date" "create_card" "$trimmed" "$assignee" "$abs_line" "$CONTEXT_BLOCK" "$desc"
        fi

        # --- Pattern: [name] action item ---
        if echo "$trimmed" | grep -qiE '^\[[a-zA-Z /]+\] '; then
            assignee=$(echo "$trimmed" | grep -oE '^\[[a-zA-Z /]+\]' | tr -d '[]')
            action_text="${trimmed#\[*\] }"
            # Only include if it's a substantive action (not just a FYI/question)
            if echo "$action_text" | grep -qiE '(to |will |should |create|file|add|update|fix|check|migrate|spike|investigate|follow.?up|open|track)'; then
                desc=$(build_description "$action_text" "$assignee" "assignee_action")
                add_action "$section_date" "assignee_action" "$action_text" "$assignee" "$abs_line" "$CONTEXT_BLOCK" "$desc"
            fi
        fi

        # --- Pattern: "Name to ..." explicit assignee ---
        if echo "$trimmed" | grep -qiE '^[A-Z][a-z]+ [A-Z][a-z]+ (to |will )'; then
            assignee=$(echo "$trimmed" | grep -oiE '^[A-Z][a-z]+ [A-Z][a-z]+')
            desc=$(build_description "$trimmed" "$assignee" "assignee_action")
            add_action "$section_date" "assignee_action" "$trimmed" "$assignee" "$abs_line" "$CONTEXT_BLOCK" "$desc"
        fi

        # --- Pattern: AI: prefix (explicit action item marker) ---
        if echo "$trimmed" | grep -qiE '^AI:'; then
            clean=$(echo "$trimmed" | sed -E 's/^AI:\s*//')
            desc=$(build_description "$clean" "" "ai_action")
            add_action "$section_date" "ai_action" "$clean" "" "$abs_line" "$CONTEXT_BLOCK" "$desc"
        fi

        # --- Pattern: "spike" / "investigate" suggestions ---
        if echo "$trimmed" | grep -qiE '\b(spike|investigate|POC|proof.of.concept)\b'; then
            assignee=""
            if echo "$trimmed" | grep -qiE '^\[[a-zA-Z /]+\]'; then
                assignee=$(echo "$trimmed" | grep -oE '^\[[a-zA-Z /]+\]' | tr -d '[]')
            fi
            desc=$(build_description "$trimmed" "$assignee" "spike")
            add_action "$section_date" "spike" "$trimmed" "$assignee" "$abs_line" "$CONTEXT_BLOCK" "$desc"
        fi

        # --- Pattern: "should we X?" / "can we X?" discussion questions suggesting a card ---
        if echo "$trimmed" | grep -qiE '^(\[[a-zA-Z /]+\] )?(should we|can we|do we want to|shall we) .*(try|add|create|use|migrate|enable|build|implement|evaluate|consider|investigate|start|move|switch)'; then
            assignee=""
            if echo "$trimmed" | grep -qiE '^\[[a-zA-Z /]+\]'; then
                assignee=$(echo "$trimmed" | grep -oE '^\[[a-zA-Z /]+\]' | tr -d '[]')
            fi
            clean="${trimmed#\[*\] }"
            desc=$(build_description "$clean" "$assignee" "suggestion")
            add_action "$section_date" "suggestion" "$clean" "$assignee" "$abs_line" "$CONTEXT_BLOCK" "$desc"
        fi

    done
done

# ============================================================================
# SCAN DOC COMMENTS ([a]..[z] blocks at bottom of plain-text export)
# These are not date-sectioned, so they need a separate pass.
# ============================================================================

echo "  Scanning inline doc comments..." >&2

linenum=0
while IFS= read -r line; do
    linenum=$((linenum + 1))
    line="${line%$'\r'}"
    trimmed="${line#"${line%%[![:space:]]*}"}"

    # Google Docs plain-text export appends comments as [a]text, [b]text, ...
    if echo "$trimmed" | grep -qE '^\[[a-zA-Z]+\]'; then
        comment_text=$(echo "$trimmed" | sed -E 's/^\[[a-zA-Z]+\]\s*//')

        if echo "$comment_text" | grep -qiE \
            'create a (card|ticket|jira|bug)|open a (ticket|jira|bug)|file a (bug|ticket)|action item|TODO|follow.?up|we (need|should) (to )?(create|open|file|track|add)'; then

            desc=$(printf "Source: %s\nLink: %s\nType: doc_comment\n\nComment text:\n%s" \
                "$FILE_NAME" "$WEB_LINK" "$comment_text")

            jq -n \
                --arg sd  "(comment)" \
                --arg t   "doc_comment" \
                --arg tx  "$comment_text" \
                --argjson l "$linenum" \
                --arg c   "$trimmed" \
                --arg d   "$desc" \
                '{section_date: $sd, type: $t, text: $tx, assignee: "", line: $l, context: $c, jira_description: $d}' >> "$TMP_ACTIONS"
        fi
    fi
done < "$TMP_DOC"

# Deduplicate by text
ACTIONS_JSON=$([ -s "$TMP_ACTIONS" ] && jq -s 'unique_by(.text)' "$TMP_ACTIONS" || echo '[]')
COUNT=$(echo "$ACTIONS_JSON" | jq 'length')

echo "Found $COUNT action(s) in the last $DAYS days (including comments)." >&2

# ============================================================================
# OUTPUT
# ============================================================================

if [ "$HUMAN" = true ]; then
    echo ""
    echo "=== $FILE_NAME — last $DAYS days — $COUNT action(s) ==="
    echo ""
    echo "$ACTIONS_JSON" | jq -r '.[] |
        "──────────────────────────────────────────",
        "[\(.type)] \(.section_date)\(.assignee | if . != "" then " — @\(.)" else "" end)",
        "Text:    \(.text)",
        "Context:",
        (.context | split("\n") | map("  " + .) | join("\n")),
        ""'
else
    jq -n \
        --arg id      "$FILE_ID" \
        --arg name    "$FILE_NAME" \
        --arg link    "$WEB_LINK" \
        --argjson days "$DAYS" \
        --argjson actions "$ACTIONS_JSON" \
        '{doc_id: $id, doc_name: $name, doc_link: $link, days: $days, total: ($actions | length), actions: $actions}'
fi
