#!/usr/bin/env bash
#
# Create a Jira issue.
#
# All fields — including those acli does not expose as flags (priority,
# components, team UUID, activity-type) — are passed via a single JSON file
# using acli's --from-json with the additionalAttributes key.
#
# Usage:
#   ./create_issue.sh <project> <summary> [options]
#
# Options:
#   --description TEXT    Issue description
#   --issuetype TYPE      Issue type (default: Task)
#   --priority NAME       Priority name (e.g., High, Critical, Medium, Low)
#   --labels l1,l2        Comma-separated labels (no spaces within labels)
#   --assignee ID         Assignee account ID or email (@me for yourself)
#   --component c1,c2     Comma-separated component names
#   --team UUID           Team UUID for customfield_10001 (not display name)
#   --epic KEY            Parent epic key (e.g., PROJ-42)
#   --epic-link-field ID  Custom field ID for epic link (used with --epic)
#   --security NAME       Security level name (e.g., "Red Hat Employee")
#   --activity-type TYPE  One of: "Tech Debt & Quality" | "New Features" | "Learning & Enablement"
#
# Output: JSON with the created issue key
# Exit codes: 0=success, 1=invalid params, 2=API error, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

DESCRIPTION=""
ISSUETYPE="Task"
PRIORITY=""
LABELS=""
ASSIGNEE=""
COMPONENT=""
TEAM=""
EPIC=""
EPIC_LINK_FIELD_ID=""
SECURITY=""
ACTIVITY_TYPE=""

if [[ $# -lt 2 ]]; then
    echo "Usage: $(basename "$0") <project> <summary> [options]" >&2
    exit 1
fi

PROJECT="$1"; shift
SUMMARY="$1"; shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --description)   DESCRIPTION="$2";   shift 2 ;;
        --issuetype)     ISSUETYPE="$2";      shift 2 ;;
        --priority)      PRIORITY="$2";       shift 2 ;;
        --labels)        LABELS="$2";         shift 2 ;;
        --assignee)      ASSIGNEE="$2";       shift 2 ;;
        --component)     COMPONENT="$2";      shift 2 ;;
        --team)          TEAM="$2";           shift 2 ;;
        --epic)          EPIC="$2";           shift 2 ;;
        --epic-link-field) EPIC_LINK_FIELD_ID="$2"; shift 2 ;;
        --security)      SECURITY="$2";       shift 2 ;;
        --activity-type) ACTIVITY_TYPE="$2";  shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -n "$ACTIVITY_TYPE" ]]; then
    case "$ACTIVITY_TYPE" in
        "Tech Debt & Quality"|"New Features"|"Learning & Enablement") ;;
        *)
            echo "ERROR: Invalid --activity-type '$ACTIVITY_TYPE'" >&2
            echo "Valid values: 'Tech Debt & Quality', 'New Features', 'Learning & Enablement'" >&2
            exit 1 ;;
    esac
fi

ensure_auth

# ---- Build JSON payload ----
# Start with required fields
JSON=$(jq -n \
    --arg project "$PROJECT" \
    --arg type    "$ISSUETYPE" \
    --arg summary "$SUMMARY" \
    '{projectKey: $project, type: $type, summary: $summary}')

if [[ -n "$DESCRIPTION" ]]; then
    ADF=$(jq -n --arg text "$DESCRIPTION" '{
        type: "doc",
        version: 1,
        content: [{
            type: "paragraph",
            content: [{ type: "text", text: $text }]
        }]
    }')
    JSON=$(echo "$JSON" | jq --argjson v "$ADF" '. + {description: $v}')
fi
[[ -n "$ASSIGNEE" ]]    && JSON=$(echo "$JSON" | jq --arg v "$ASSIGNEE"    '. + {assignee: $v}')

# ---- additionalAttributes for fields acli does not expose as flags ----
EXTRA="{}"

if [[ -n "$EPIC" ]]; then
    if [[ -n "$EPIC_LINK_FIELD_ID" ]]; then
        EXTRA=$(echo "$EXTRA" | jq --arg field "$EPIC_LINK_FIELD_ID" --arg v "$EPIC" \
            '. + {($field): $v}')
    else
        JSON=$(echo "$JSON" | jq --arg v "$EPIC" '. + {parentIssueId: $v}')
    fi
fi

if [[ -n "$LABELS" ]]; then
    LABELS_JSON=$(printf '%s' "$LABELS" | jq -R 'split(",") | map(ltrimstr(" ") | rtrimstr(" ")) | map(select(. != ""))')
    JSON=$(echo "$JSON" | jq --argjson v "$LABELS_JSON" '. + {labels: $v}')
fi

[[ -n "$PRIORITY" ]] && EXTRA=$(echo "$EXTRA" | jq --arg v "$PRIORITY" \
    '. + {priority: {name: $v}}')

[[ -n "$SECURITY" ]] && EXTRA=$(echo "$EXTRA" | jq --arg v "$SECURITY" \
    '. + {security: {name: $v}}')

if [[ -n "$COMPONENT" ]]; then
    COMP_JSON=$(printf '%s' "$COMPONENT" | jq -R 'split(",") | map(ltrimstr(" ") | rtrimstr(" ")) | map(select(. != "")) | map({name: .})')
    EXTRA=$(echo "$EXTRA" | jq --argjson v "$COMP_JSON" '. + {components: $v}')
fi

[[ -n "$TEAM" ]] && EXTRA=$(echo "$EXTRA" | jq --arg v "$TEAM" \
    '. + {customfield_10001: $v}')

[[ -n "$ACTIVITY_TYPE" ]] && EXTRA=$(echo "$EXTRA" | jq --arg v "$ACTIVITY_TYPE" \
    '. + {customfield_10464: {value: $v}}')

if [[ "$EXTRA" != "{}" ]]; then
    JSON=$(echo "$JSON" | jq --argjson v "$EXTRA" '. + {additionalAttributes: $v}')
fi

# ---- Write temp file and create via acli ----
TMPFILE=$(make_tmp_json "$JSON")
trap 'rm -f "$TMPFILE"' EXIT

echo "Creating $ISSUETYPE in $PROJECT: '$SUMMARY'..." >&2
acli jira workitem create --from-json "$TMPFILE" --json
