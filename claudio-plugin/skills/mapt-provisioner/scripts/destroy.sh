#!/usr/bin/env bash
#
# Destroy a mapt-provisioned target.
#
# Usage:
#   ./destroy.sh --provider <aws|azure> --target <rhel-ai|openshift-snc|...> --project-name <name>
#
# Required environment variables:
#   MAPT_BACKEND_URL - Pulumi state backend URL
#   Provider-specific credentials (AWS or Azure)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROVIDER=""
TARGET=""
PROJECT_NAME=""
FORCE_DESTROY=false

usage() {
    echo "Usage: $(basename "$0") --provider <aws|azure> --target <target> --project-name <name>"
    echo ""
    echo "Options:"
    echo "  --provider        Cloud provider: aws or azure (required)"
    echo "  --target          Target type: rhel-ai, openshift-snc, rhel, fedora, etc. (required)"
    echo "  --project-name    Stack identifier used during provisioning (required)"
    echo "  --force-destroy   Force destroy even if Pulumi lock is stale"
    echo ""
    echo "Supported targets by provider:"
    echo "  AWS:   rhel-ai, openshift-snc, rhel, fedora, mac, kind, eks"
    echo "  Azure: rhel-ai, rhel, fedora, windows, ubuntu, kind, aks"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) require_arg "$1" "${2:-}"; PROVIDER="$2"; shift 2 ;;
        --target) require_arg "$1" "${2:-}"; TARGET="$2"; shift 2 ;;
        --project-name) require_arg "$1" "${2:-}"; PROJECT_NAME="$2"; shift 2 ;;
        --force-destroy) FORCE_DESTROY=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

if [[ -z "$PROVIDER" ]]; then
    echo "ERROR: --provider is required" >&2
    usage
fi

if [[ -z "$TARGET" ]]; then
    echo "ERROR: --target is required" >&2
    usage
fi

if [[ -z "$PROJECT_NAME" ]]; then
    echo "ERROR: --project-name is required" >&2
    usage
fi

validate_backend_url
validate_provider_credentials "$PROVIDER"

case "$PROVIDER:$TARGET" in
    aws:rhel-ai|aws:openshift-snc|aws:rhel|aws:fedora|aws:mac|aws:kind|aws:eks|\
    azure:rhel-ai|azure:rhel|azure:fedora|azure:windows|azure:ubuntu|azure:kind|azure:aks)
        ;;
    *)
        echo "ERROR: Target '$TARGET' is not supported for provider '$PROVIDER'" >&2
        usage
        ;;
esac

echo "Destroying mapt target..."
echo "  Provider:      $PROVIDER"
echo "  Target:        $TARGET"
echo "  Project:       $PROJECT_NAME"
echo "  State backend: [configured]"
echo ""

CMD=(mapt "$PROVIDER" "$TARGET" destroy
    --project-name "$PROJECT_NAME"
    --backed-url "$MAPT_BACKEND_URL"
)

[[ "$FORCE_DESTROY" = true ]] && CMD+=(--force-destroy)

"${CMD[@]}"

echo ""
echo "✓ Target destroyed successfully"
