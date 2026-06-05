#!/usr/bin/env bash
#
# Check status of a mapt-provisioned target.
#
# Usage:
#   ./check_status.sh --project-name <name> [--conn-details-output <path>]
#
# Required environment variables:
#   MAPT_BACKEND_URL - Pulumi state backend URL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_NAME=""
CONN_DETAILS_OUTPUT=""

usage() {
    echo "Usage: $(basename "$0") --project-name <name> [--conn-details-output <path>]"
    echo ""
    echo "Options:"
    echo "  --project-name          Stack identifier (required)"
    echo "  --conn-details-output   Path to check for connection details (default: /tmp/mapt-conn-details)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name) require_arg "$1" "${2:-}"; PROJECT_NAME="$2"; shift 2 ;;
        --conn-details-output) require_arg "$1" "${2:-}"; CONN_DETAILS_OUTPUT="$2"; shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

if [[ -z "$PROJECT_NAME" ]]; then
    echo "ERROR: --project-name is required" >&2
    usage
fi

validate_backend_url

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed" >&2
    exit 1
fi

CONN_DETAILS_OUTPUT="${CONN_DETAILS_OUTPUT:-$DEFAULT_CONN_DETAILS_OUTPUT/$PROJECT_NAME}"

echo "Checking status for project: $PROJECT_NAME"
echo "  State backend: [configured]"
echo ""

if ! STACK_INFO=$(PULUMI_BACKEND_URL="$MAPT_BACKEND_URL" pulumi stack ls --json --all); then
    echo "ERROR: Failed to query Pulumi backend. Check MAPT_BACKEND_URL and credentials." >&2
    exit 1
fi

if ! echo "$STACK_INFO" | jq '.' >/dev/null; then
    echo "ERROR: Pulumi returned invalid JSON. Raw output:" >&2
    echo "$STACK_INFO" >&2
    exit 1
fi

if echo "$STACK_INFO" | jq -e --arg name "$PROJECT_NAME" '.[] | select(.name | contains($name))' >/dev/null; then
    echo "✓ Project '$PROJECT_NAME' exists in state backend"
    echo ""
    echo "Stack details:"
    echo "$STACK_INFO" | jq -r --arg name "$PROJECT_NAME" '
        .[] | select(.name | contains($name)) |
        "  Name:          \(.name // "N/A")",
        "  Last updated:  \(.lastUpdate // "N/A")",
        "  Resource count: \(.resourceCount // "N/A")"
    '
else
    echo "✗ Project '$PROJECT_NAME' not found in state backend"
    exit 1
fi

echo ""
if [[ -d "$CONN_DETAILS_OUTPUT" ]]; then
    log_connection_details "$CONN_DETAILS_OUTPUT"
else
    echo "No connection details found at $CONN_DETAILS_OUTPUT"
fi
