#!/usr/bin/env bash
#
# Create Jira issues from extracted actions (reads JSON from stdin or file).
#
# Reads the output of extract_actions.sh and creates one Jira issue per action.
#
# Usage:
#   extract_actions.sh <file-id> | ./create_jira_cards.sh --project <PROJECT-KEY> [OPTIONS]
#   ./create_jira_cards.sh --project <PROJECT-KEY> --input actions.json [OPTIONS]
#
# Options:
#   --project KEY     Jira project key (required)
#   --type TYPE       Issue type: Task (default), Bug, Story
#   --input FILE      Read from file instead of stdin
#   --dry-run         Print what would be created without calling Jira
#
# Required env vars:
#   JIRA_SITE         Atlassian hostname (e.g. yourorg.atlassian.net)
#   JIRA_TOKEN        Atlassian API token
#   JIRA_EMAIL        Atlassian account email

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIRA_SCRIPTS="$SCRIPT_DIR/../../jira-utilities/scripts"

PROJECT=""
ISSUE_TYPE="Task"
INPUT_FILE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --project)
            [[ $# -gt 1 ]] || { echo "ERROR: Missing value for --project" >&2; exit 1; }
            PROJECT="$2";    shift 2 ;;
        --type)
            [[ $# -gt 1 ]] || { echo "ERROR: Missing value for --type" >&2; exit 1; }
            ISSUE_TYPE="$2"; shift 2 ;;
        --input)
            [[ $# -gt 1 ]] || { echo "ERROR: Missing value for --input" >&2; exit 1; }
            INPUT_FILE="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true;    shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$PROJECT" ]; then
    echo "ERROR: --project KEY is required" >&2
    exit 1
fi

# Read input JSON
if [ -n "$INPUT_FILE" ]; then
    PAYLOAD=$(cat "$INPUT_FILE")
else
    PAYLOAD=$(cat)
fi

if ! echo "$PAYLOAD" | jq -e 'has("actions") and (.actions | type == "array")' >/dev/null 2>&1; then
    echo "ERROR: Input JSON must have an 'actions' array field" >&2
    exit 1
fi

DOC_NAME=$(echo "$PAYLOAD" | jq -r '.doc_name // "Unknown doc"')
DOC_LINK=$(echo "$PAYLOAD" | jq -r '.doc_link // ""')
ACTIONS=$(echo "$PAYLOAD" | jq -c '.actions[]')

if [ -z "$ACTIONS" ]; then
    echo "No actions found in input." >&2
    exit 0
fi

# Verify Jira env vars early to fail fast before processing any actions
if [ "$DRY_RUN" = false ]; then
    if [ -z "${JIRA_SITE:-}" ] || [ -z "${JIRA_TOKEN:-}" ] || [ -z "${JIRA_EMAIL:-}" ]; then
        echo "ERROR: JIRA_SITE, JIRA_TOKEN, and JIRA_EMAIL must be set" >&2
        exit 1
    fi
fi

CREATED=()
FAILED=()

while IFS= read -r action; do
    TYPE=$(echo "$action"    | jq -r '.type')
    TEXT=$(echo "$action"    | jq -r '.text')
    ASSIGNEE=$(echo "$action" | jq -r '.assignee // ""')
    LINE=$(echo "$action"    | jq -r '.line')
    CONTEXT=$(echo "$action" | jq -r '.context')

    # Build Jira summary (cap at 200 chars)
    SUMMARY=$(echo "$TEXT" | cut -c1-200)

    # Build description
    DESCRIPTION=$(printf 'Action extracted from Google Doc: %s\nSource link: %s\n\nPattern type: %s\nLine: %s\nContext: %s' \
        "$DOC_NAME" "$DOC_LINK" "$TYPE" "$LINE" "$CONTEXT")
    if [ -n "$ASSIGNEE" ]; then
        DESCRIPTION=$(printf '%s\nMentioned assignee: %s' "$DESCRIPTION" "$ASSIGNEE")
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would create $ISSUE_TYPE in $PROJECT:"
        echo "  Summary:     $SUMMARY"
        echo "  Assignee:    ${ASSIGNEE:-<unset>}"
        echo "  Description: (from doc line $LINE)"
        echo ""
    else
        echo "Creating Jira $ISSUE_TYPE: $SUMMARY" >&2

        RESULT=$("$JIRA_SCRIPTS/create_issue.sh" \
            "$PROJECT" \
            "$SUMMARY" \
            --issuetype   "$ISSUE_TYPE" \
            --description "$DESCRIPTION") || {
            echo "FAILED: $SUMMARY" >&2
            FAILED+=("$SUMMARY")
            continue
        }

        KEY=$(echo "$RESULT" | jq -r '.key // .id // "unknown"')
        echo "Created: $KEY — $SUMMARY" >&2
        CREATED+=("$KEY")
    fi
done <<< "$ACTIONS"

# Summary output
if [ "$DRY_RUN" = false ]; then
    if [ "${#CREATED[@]}" -gt 0 ]; then
        CREATED_JSON=$(printf '%s\n' "${CREATED[@]}" | jq -R . | jq -s .)
    else
        CREATED_JSON="[]"
    fi
    if [ "${#FAILED[@]}" -gt 0 ]; then
        FAILED_JSON=$(printf '%s\n' "${FAILED[@]}" | jq -R . | jq -s .)
    else
        FAILED_JSON="[]"
    fi
    jq -n \
        --argjson created "$CREATED_JSON" \
        --argjson failed  "$FAILED_JSON" \
        '{created: $created, failed: $failed}'
fi
