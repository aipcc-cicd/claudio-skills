#!/usr/bin/env bash
#
# Provision a RHELAI instance using mapt.
#
# Usage:
#   ./provision_rhelai.sh --provider <aws|azure> [options]
#
# Required environment variables:
#   MAPT_BACKEND_URL - Pulumi state backend URL
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (for --provider aws)
#   ARM_TENANT_ID / ARM_SUBSCRIPTION_ID / ARM_CLIENT_ID / ARM_CLIENT_SECRET (for --provider azure)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Defaults
PROVIDER=""
PROJECT_NAME=""
VERSION=""
CPUS=""
MEMORY=""
GPUS=""
DISK_SIZE=""
ACCELERATOR=""
COMPUTE_SIZES=""
SPOT_EVICTION_TOLERANCE=""
TAGS=""
SPOT=false
CONN_DETAILS_OUTPUT=""

usage() {
    echo "Usage: $(basename "$0") --provider <aws|azure> [options]"
    echo ""
    echo "Options:"
    echo "  --provider              Cloud provider: aws or azure (required)"
    echo "  --project-name          Stack identifier (default: auto-generated)"
    echo "  --version               RHELAI version (auto-discovered for both aws and azure)"
    echo "  --cpus                  Number of CPUs"
    echo "  --memory                Memory in GiB"
    echo "  --gpus                  Number of GPUs"
    echo "  --disk-size             Disk size in GB"
    echo "  --accelerator               GPU accelerator: cuda or rocm (mapt default: cuda)"
    echo "  --compute-sizes             Comma-separated VM sizes to constrain spot selection (e.g. Standard_E8s_v5,Standard_E16s_v5)"
    echo "  --spot-eviction-tolerance   Spot tolerance: lowest, low, medium, high, highest (default: highest when --spot)"
    echo "  --tags                      Key=value tags for cost attribution (e.g. team=myteam,env=dev)"
    echo "  --spot                      Use spot instances"
    echo "  --conn-details-output   Path for connection details (default: /tmp/mapt-conn-details)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) require_arg "$1" "${2:-}"; PROVIDER="$2"; shift 2 ;;
        --project-name) require_arg "$1" "${2:-}"; PROJECT_NAME="$2"; shift 2 ;;
        --version) require_arg "$1" "${2:-}"; VERSION="$2"; shift 2 ;;
        --cpus) require_arg "$1" "${2:-}"; CPUS="$2"; shift 2 ;;
        --memory) require_arg "$1" "${2:-}"; MEMORY="$2"; shift 2 ;;
        --gpus) require_arg "$1" "${2:-}"; GPUS="$2"; shift 2 ;;
        --disk-size) require_arg "$1" "${2:-}"; DISK_SIZE="$2"; shift 2 ;;
        --accelerator) require_arg "$1" "${2:-}"; ACCELERATOR="$2"; shift 2 ;;
        --compute-sizes) require_arg "$1" "${2:-}"; COMPUTE_SIZES="$2"; shift 2 ;;
        --spot-eviction-tolerance) require_arg "$1" "${2:-}"; SPOT_EVICTION_TOLERANCE="$2"; shift 2 ;;
        --tags) require_arg "$1" "${2:-}"; TAGS="$2"; shift 2 ;;
        --spot) SPOT=true; shift ;;
        --conn-details-output) require_arg "$1" "${2:-}"; CONN_DETAILS_OUTPUT="$2"; shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

if [[ -z "$PROVIDER" ]]; then
    echo "ERROR: --provider is required" >&2
    usage
fi

validate_backend_url
validate_provider_credentials "$PROVIDER"

# Default spot-eviction-tolerance to highest when using spot — GPU workloads
# provisioned through this skill are typically testing/demo, not production.
if [[ "$SPOT" = true && -z "$SPOT_EVICTION_TOLERANCE" ]]; then
    SPOT_EVICTION_TOLERANCE="highest"
fi

# For Azure, discover the latest available gallery image version when not specified
if [[ "$PROVIDER" == "azure" && -z "$VERSION" ]]; then
    echo "Discovering latest RHEL AI version in Azure gallery..."
    ACCEL_ARG="${ACCELERATOR:-cuda}"
    VERSIONS=$(mapt azure rhel-ai list-versions --accelerator "$ACCEL_ARG")
    if [[ -z "${VERSIONS//[[:space:]]/}" ]]; then
        echo "ERROR: no Azure RHEL AI versions returned for accelerator '${ACCEL_ARG}'." >&2
        exit 1
    fi
    # Prefer stable (non-EA); fall back to EA only if no stable exists.
    STABLE=$(echo "$VERSIONS" | { grep -v "\-ea" || true; } | tail -1)
    VERSION="${STABLE:-$(echo "$VERSIONS" | tail -1)}"
    echo "  Found version: $VERSION"
    if [[ "$VERSION" == *"-ea"* ]]; then
        echo "" >&2
        echo "ERROR: Only Early Access (EA) versions are available for accelerator '${ACCEL_ARG}' in the gallery." >&2
        echo "  Discovered version: $VERSION" >&2
        echo "" >&2
        echo "  EA versions are pre-release and may cause failures. Options:" >&2
        echo "    1. Use a different accelerator: --accelerator rocm" >&2
        echo "    2. Proceed explicitly: --version $VERSION --accelerator $ACCEL_ARG" >&2
        exit 1
    fi
fi

# For AWS, discover the latest available AMI version when not specified
if [[ "$PROVIDER" == "aws" && -z "$VERSION" ]]; then
    echo "Discovering latest RHEL AI version in AWS..."
    ACCEL_ARG="${ACCELERATOR:-cuda}"
    VERSIONS=$(mapt aws rhel-ai list-versions --accelerator "$ACCEL_ARG")
    if [[ -z "${VERSIONS//[[:space:]]/}" ]]; then
        echo "ERROR: no AWS RHEL AI versions returned for accelerator '${ACCEL_ARG}'." >&2
        exit 1
    fi
    # Prefer stable (non-EA); fall back to EA only if no stable exists.
    STABLE=$(echo "$VERSIONS" | { grep -v "\-ea" || true; } | tail -1)
    VERSION="${STABLE:-$(echo "$VERSIONS" | tail -1)}"
    echo "  Found version: $VERSION"
    if [[ "$VERSION" == *"-ea"* ]]; then
        echo "" >&2
        echo "ERROR: Only Early Access (EA) versions are available for accelerator '${ACCEL_ARG}' in AWS." >&2
        echo "  Discovered version: $VERSION" >&2
        echo "" >&2
        echo "  EA versions are pre-release and may cause failures. Options:" >&2
        echo "    1. Use a different accelerator: --accelerator rocm" >&2
        echo "    2. Proceed explicitly: --version $VERSION --accelerator $ACCEL_ARG" >&2
        exit 1
    fi
fi

if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME=$(generate_project_name "rhelai")
fi
CONN_DETAILS_OUTPUT="${CONN_DETAILS_OUTPUT:-$DEFAULT_CONN_DETAILS_OUTPUT/$PROJECT_NAME}"

echo "Provisioning RHELAI instance..."
echo "  Provider:     $PROVIDER"
echo "  Project:      $PROJECT_NAME"
echo "  Version:      ${VERSION:-(mapt default)}"
echo "  State backend: [configured]"

CMD=(mapt "$PROVIDER" rhel-ai create
    --project-name "$PROJECT_NAME"
    --backed-url "$MAPT_BACKEND_URL"
    --conn-details-output "$CONN_DETAILS_OUTPUT"
)
[[ -n "$VERSION" ]] && CMD+=(--version "$VERSION")

[[ -n "$CPUS" ]] && CMD+=(--cpus "$CPUS")
[[ -n "$MEMORY" ]] && CMD+=(--memory "$MEMORY")
[[ -n "$GPUS" ]] && CMD+=(--gpus "$GPUS")
[[ -n "$DISK_SIZE" ]] && CMD+=(--disk-size "$DISK_SIZE")
[[ -n "$ACCELERATOR" ]] && CMD+=(--accelerator "$ACCELERATOR")
[[ -n "$COMPUTE_SIZES" ]] && CMD+=(--compute-sizes "$COMPUTE_SIZES")
[[ -n "$SPOT_EVICTION_TOLERANCE" ]] && CMD+=(--spot-eviction-tolerance "$SPOT_EVICTION_TOLERANCE")
[[ -n "$TAGS" ]] && CMD+=(--tags "$TAGS")
[[ "$SPOT" = true ]] && CMD+=(--spot)

echo "  Command:      ${CMD[*]//$MAPT_BACKEND_URL/[configured]}"
echo ""

mkdir -p "$CONN_DETAILS_OUTPUT"
"${CMD[@]}"

echo ""
echo "✓ RHELAI instance provisioned successfully"
echo "  Project name: $PROJECT_NAME (use this to destroy later)"
echo ""
log_connection_details "$CONN_DETAILS_OUTPUT"
