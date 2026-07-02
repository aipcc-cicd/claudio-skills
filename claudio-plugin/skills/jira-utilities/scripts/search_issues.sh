#!/usr/bin/env bash
#
# Search Jira issues using JQL, a keyword, or an epic key.
#
# Usage:
#   ./search_issues.sh '<jql>'
#   ./search_issues.sh --search KEYWORD [--project PROJ]
#   ./search_issues.sh --epic EPIC-KEY
#
# Options:
#   --max-results N     Max results (default: 50; use 0 to paginate all)
#   --fields f1,f2      Comma-separated fields to include
#   --format json|table Output format (default: json)
#   --project KEY       Restrict --search to a specific project key
#
# Examples:
#   ./search_issues.sh 'project = PROJ AND status = "Open"'
#   ./search_issues.sh --search "login timeout"
#   ./search_issues.sh --search "auth" --project MYPROJ --format table
#   ./search_issues.sh --epic PROJ-42
#   ./search_issues.sh 'assignee = currentUser()' --max-results 0
#
# Exit codes: 0=success, 1=invalid params, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

MAX_RESULTS=50
FIELDS=""
FORMAT="json"
SEARCH_KEYWORD=""
EPIC_KEY=""
PROJECT=""
JQL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --search)       SEARCH_KEYWORD="$2"; shift 2 ;;
        --epic|--parent) [[ $# -lt 2 || -z "$2" ]] && { echo "ERROR: --epic/--parent requires a value" >&2; exit 1; }
                         EPIC_KEY="$2"; shift 2 ;;
        --project)      PROJECT="$2";         shift 2 ;;
        --max-results)  MAX_RESULTS="$2";     shift 2 ;;
        --fields)       FIELDS="$2";          shift 2 ;;
        --format)       FORMAT="$2";          shift 2 ;;
        --*)            echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
        *)              JQL="$1";             shift ;;
    esac
done

# Validate mutual exclusivity
input_count=0
[[ -n "$JQL" ]]            && ((input_count++)) || true
[[ -n "$SEARCH_KEYWORD" ]] && ((input_count++)) || true
[[ -n "$EPIC_KEY" ]]       && ((input_count++)) || true

if [[ $input_count -eq 0 ]]; then
    echo "ERROR: provide a JQL query, --search KEYWORD, or --epic KEY." >&2
    exit 1
fi
if [[ $input_count -gt 1 ]]; then
    echo "ERROR: provide only one of: JQL query, --search, or --epic." >&2
    exit 1
fi

if [[ "$FORMAT" != "json" && "$FORMAT" != "table" ]]; then
    echo "ERROR: --format must be 'json' or 'table'" >&2
    exit 1
fi

# Build JQL for convenience modes
if [[ -n "$SEARCH_KEYWORD" ]]; then
    ESCAPED="${SEARCH_KEYWORD//\"/\\\"}"
    JQL="text ~ \"${ESCAPED}\""
    [[ -n "$PROJECT" ]] && JQL="project = ${PROJECT} AND ${JQL}"
elif [[ -n "$EPIC_KEY" ]]; then
    # parent first: covers next-gen and Initiative→Epic hierarchy.
    # "Epic Link" fallback covers classic project types.
    JQL="parent = ${EPIC_KEY} OR \"Epic Link\" = ${EPIC_KEY}"
fi

ensure_auth

echo "Searching: $JQL" >&2

CMD=(acli jira workitem search --jql "$JQL")

if [[ "$MAX_RESULTS" -eq 0 ]]; then
    CMD+=(--paginate)
else
    CMD+=(--limit "$MAX_RESULTS")
fi

# Bug 1: acli rejects date field names in --fields (created, updated, etc.).
# Strip them, warn, and let the caller extract timestamps from .fields.* in the JSON payload.
# Bug 3: acli rejects --fields entirely in table mode; skip it with a warning.
if [[ -n "$FIELDS" && "$FORMAT" != "table" ]]; then
    DATE_FIELDS_PATTERN="^(created|updated|resolutiondate|updateddate|createddate)$"
    SAFE_FIELDS=$(echo "$FIELDS" | tr ',' '\n' | { grep -Eiv "$DATE_FIELDS_PATTERN" || true; } | paste -sd ',' -)
    DATE_ONLY_FIELDS=$(echo "$FIELDS" | tr ',' '\n' | { grep -Ei "$DATE_FIELDS_PATTERN" || true; } | paste -sd ',' -)
    if [[ -n "$DATE_ONLY_FIELDS" ]]; then
        echo "WARN: acli does not support --fields $DATE_ONLY_FIELDS; timestamps are available in the JSON payload via .fields.created / .fields.updated." >&2
    fi
    [[ -n "$SAFE_FIELDS" ]] && CMD+=(--fields "$SAFE_FIELDS")
elif [[ -n "$FIELDS" && "$FORMAT" == "table" ]]; then
    echo "WARN: --fields is ignored in table mode." >&2
fi

if [[ "$FORMAT" == "table" ]]; then
    # acli exits 1 on empty results — tolerate it so empty searches don't
    # look like failures when set -euo pipefail is active.
    "${CMD[@]}" || {
        code=$?
        [[ $code -eq 1 ]] && echo "(no results)" >&2 && exit 0
        exit $code
    }
else
    CMD+=(--json)
    # Bug 2: acli's spinner writes ANSI control characters to stdout, corrupting JSON.
    # Capture output, strip escape sequences, then extract the JSON.
    TMPOUT=$(mktemp)
    trap 'rm -f "$TMPOUT"' EXIT
    "${CMD[@]}" > "$TMPOUT"
    CLEAN=$(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' "$TMPOUT")
    jq '.' <<< "$CLEAN" 2>/dev/null \
        || sed -n '/^\[/,/^\]/p; /^{/,/^}/p' <<< "$CLEAN" | jq '.'
fi
