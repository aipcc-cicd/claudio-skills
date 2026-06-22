#!/usr/bin/env bash
#
# Provision an OpenShift Single Node Cluster (SNC) using mapt.
# AWS only - mapt does not support Azure SNC.
#
# Usage:
#   ./provision_snc.sh [options]
#
# Required environment variables:
#   MAPT_BACKEND_URL         - Pulumi state backend URL
#   AWS_ACCESS_KEY_ID       - AWS access key
#   AWS_SECRET_ACCESS_KEY   - AWS secret key
#   PULL_SECRET_FILE        - Path to OpenShift pull secret file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Defaults
PROJECT_NAME=""
VERSION="4.21.0"
PROFILE=""
ARCH=""
TAGS=""
SPOT=false
SPOT_EVICTION_TOLERANCE=""
CONN_DETAILS_OUTPUT=""

usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Options:"
    echo "  --project-name          Stack identifier (default: auto-generated)"
    echo "  --version               OpenShift version (default: 4.21.0)"
    echo "  --pull-secret-file      Path to pull secret (overrides PULL_SECRET_FILE env var)"
    echo "  --profile               Comma-separated profiles: virtualization, serverless,"
    echo "                          serverless-serving, serverless-eventing, servicemesh, ai, nvidia"
    echo "  --arch                  Architecture: x86_64 or arm64 (mapt default: x86_64)"
    echo "  --tags                  Key=value tags for cost attribution (e.g. team=myteam,env=dev)"
    echo "  --spot                  Use spot instances"
    echo "  --spot-eviction-tolerance   Spot tolerance: lowest, low, medium, high, highest (default: highest when --spot)"
    echo "  --conn-details-output   Path for connection details (default: /tmp/mapt-conn-details)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name) require_arg "$1" "${2:-}"; PROJECT_NAME="$2"; shift 2 ;;
        --version) require_arg "$1" "${2:-}"; VERSION="$2"; shift 2 ;;
        --pull-secret-file) require_arg "$1" "${2:-}"; PULL_SECRET_FILE="$2"; shift 2 ;;
        --profile) require_arg "$1" "${2:-}"; PROFILE="$2"; shift 2 ;;
        --arch) require_arg "$1" "${2:-}"; ARCH="$2"; shift 2 ;;
        --tags) require_arg "$1" "${2:-}"; TAGS="$2"; shift 2 ;;
        --spot) SPOT=true; shift ;;
        --spot-eviction-tolerance) require_arg "$1" "${2:-}"; SPOT_EVICTION_TOLERANCE="$2"; shift 2 ;;
        --conn-details-output) require_arg "$1" "${2:-}"; CONN_DETAILS_OUTPUT="$2"; shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

validate_backend_url
validate_aws_credentials
validate_pull_secret

if [[ "$SPOT" = true && -z "$SPOT_EVICTION_TOLERANCE" ]]; then
    SPOT_EVICTION_TOLERANCE="highest"
fi

if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME=$(generate_project_name "snc")
fi
CONN_DETAILS_OUTPUT="${CONN_DETAILS_OUTPUT:-$DEFAULT_CONN_DETAILS_OUTPUT/$PROJECT_NAME}"

echo "Provisioning OpenShift SNC..."
echo "  Provider:      AWS"
echo "  Project:       $PROJECT_NAME"
echo "  Version:       $VERSION"
echo "  Pull secret:   $PULL_SECRET_FILE"
echo "  State backend: [configured]"

CMD=(mapt aws openshift-snc create
    --project-name "$PROJECT_NAME"
    --backed-url "$MAPT_BACKEND_URL"
    --version "$VERSION"
    --pull-secret-file "$PULL_SECRET_FILE"
    --conn-details-output "$CONN_DETAILS_OUTPUT"
)

[[ -n "$PROFILE" ]] && CMD+=(--profile "$PROFILE")
[[ -n "$ARCH" ]] && CMD+=(--arch "$ARCH")
[[ -n "$TAGS" ]] && CMD+=(--tags "$TAGS")
[[ "$SPOT" = true ]] && CMD+=(--spot)
[[ -n "$SPOT_EVICTION_TOLERANCE" ]] && CMD+=(--spot-eviction-tolerance "$SPOT_EVICTION_TOLERANCE")

echo "  Command:       ${CMD[*]//$MAPT_BACKEND_URL/[configured]}"
echo ""

mkdir -p "$CONN_DETAILS_OUTPUT"
"${CMD[@]}"

echo ""
echo "✓ OpenShift SNC provisioned successfully"
echo "  Project name: $PROJECT_NAME (use this to destroy later)"
echo ""
log_connection_details "$CONN_DETAILS_OUTPUT"
