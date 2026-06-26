#!/usr/bin/env bash
#
# Fetch comments for a Jira issue.
#
# Usage:
#   ./get_issue_comments.sh <issue_key>
#
# Example:
#   ./get_issue_comments.sh PROJ-123
#
# Output: JSON array of comment objects
# Exit codes: 0=success, 1=invalid params

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") <issue_key>" >&2
    exit 1
fi

KEY="$1"

if [[ ! "$KEY" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
    echo "ERROR: Invalid issue key format: '$KEY' (expected e.g. PROJ-123)" >&2
    exit 1
fi

require_env

echo "Fetching comments for $KEY..." >&2
jira_rest GET "/rest/api/2/issue/${KEY}/comment" \
    | jq '.comments'
