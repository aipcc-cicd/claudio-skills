#!/usr/bin/env bash
# Fetch available team components from a Jira project.
# Usage: list_teams.sh <project>
# Outputs: JSON array of component names, sorted alphabetically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIRA_UTILS="$(cd "$SCRIPT_DIR/../../jira-utilities/scripts" && pwd)"
source "$JIRA_UTILS/_common.sh"

EXIT_INVALID_PARAMS=1
EXIT_NETWORK_ERROR=2
EXIT_AUTH_ERROR=3

project="${1:-}"
if [[ -z "$project" ]]; then
    echo "Usage: $0 <project>" >&2
    echo "Example: $0 AIPCC" >&2
    exit "$EXIT_INVALID_PARAMS"
fi

if [[ ! "$project" =~ ^[A-Z][A-Z0-9]+$ ]]; then
    echo "Invalid project key: ${project}" >&2
    exit "$EXIT_INVALID_PARAMS"
fi

if ! (require_env 2>/dev/null); then
    echo "Missing required Jira environment variables (JIRA_SITE, JIRA_TOKEN, JIRA_EMAIL)" >&2
    exit "$EXIT_AUTH_ERROR"
fi

set +e
response=$(jira_rest GET "/rest/api/2/project/${project}/components" 2>/dev/null)
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
    echo "Failed to fetch components from project ${project}" >&2
    exit "$EXIT_NETWORK_ERROR"
fi

echo "$response" | jq '[.[].name] | sort'
