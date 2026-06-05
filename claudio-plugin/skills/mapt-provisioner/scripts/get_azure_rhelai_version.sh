#!/usr/bin/env bash
#
# Discover the latest RHEL AI version available in the Azure Compute Gallery
# for the given accelerator type, across all resource groups in the subscription.
#
# Usage:
#   ./get_azure_rhelai_version.sh [--accelerator cuda|rocm]
#
# Outputs: the latest version string (e.g. "3.2.0") on stdout
#
# Required environment variables:
#   ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID
#   AZURE_GALLERY_RESOURCE_GROUP - resource group mapt uses for image lookups (e.g. aipcc-productization)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

validate_azure_credentials

ACCELERATOR="cuda"

while [[ $# -gt 0 ]]; do
    case $1 in
        --accelerator) require_arg "$1" "${2:-}"; ACCELERATOR="$2"; shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "${AZURE_GALLERY_RESOURCE_GROUP:-}" ]]; then
    echo "ERROR: AZURE_GALLERY_RESOURCE_GROUP is required (resource group mapt uses for image lookups)" >&2
    exit 1
fi
GALLERY_PREFIX="rhel_ai_${ACCELERATOR}_azure_"

# Authenticate with service principal and get access token
# Use -d with pre-encoded scope; --data-urlencode corrupts client_secret when
# the secret contains special characters, causing Azure to reject the request.
TOKEN=$(curl -sf -X POST \
    "https://login.microsoftonline.com/${ARM_TENANT_ID}/oauth2/v2.0/token" \
    -d "grant_type=client_credentials&client_id=${ARM_CLIENT_ID}&client_secret=${ARM_CLIENT_SECRET}&scope=https%3A%2F%2Fmanagement.azure.com%2F.default" \
    | jq -r '.access_token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
    echo "ERROR: Failed to obtain Azure access token" >&2
    exit 1
fi

# List galleries in the subscription filtered to the target resource group.
# Filtering by RG is critical: galleries in other RGs (e.g. RHEL-AI-CUDA-AZURE-3.0.0)
# are unreachable by mapt, which hardcodes the RG for image lookups.
# Comparison is case-insensitive because Azure normalises RG names to uppercase in resource IDs.
GALLERIES=$(curl -sf \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/providers/Microsoft.Compute/galleries?api-version=2022-03-03" \
    | jq -r --arg rg "${AZURE_GALLERY_RESOURCE_GROUP}" \
        '.value[] | select(.id | ascii_downcase | contains("/resourcegroups/\($rg | ascii_downcase)/")) | .name')

# Filter for rhel_ai_{accelerator}_azure_* and extract versions.
# Gallery names use all underscores (mapt replaces all hyphens with underscores when
# building gallery names), so convert back to hyphens to get the correct version string
# to pass to mapt (e.g. gallery "rhel_ai_cuda_azure_3.4.0_ea.2" → version "3.4.0-ea.2").
VERSIONS=$(echo "$GALLERIES" \
    | { grep "^${GALLERY_PREFIX}" || true; } \
    | sed "s/^${GALLERY_PREFIX}//" \
    | tr '_' '-')

if [[ -z "$VERSIONS" ]]; then
    echo "ERROR: No RHEL AI images found for accelerator '${ACCELERATOR}' in subscription" >&2
    echo "  Available galleries:" >&2
    echo "$GALLERIES" | grep "^rhel_ai_" >&2 || echo "  (none)" >&2
    exit 1
fi

# Prefer stable (non-EA) versions; fall back to EA only if no stable exists.
# grep exits 1 on no match so use || true to avoid killing the script under pipefail.
STABLE=$(echo "$VERSIONS" | { grep -v "\-ea" || true; } | sort -V | tail -1)
LATEST="${STABLE:-$(echo "$VERSIONS" | sort -V | tail -1)}"

if [[ -z "$STABLE" ]]; then
    echo "WARNING: Only EA versions available for accelerator '${ACCELERATOR}'. Consider passing --version and --accelerator explicitly." >&2
fi

echo "$LATEST"
