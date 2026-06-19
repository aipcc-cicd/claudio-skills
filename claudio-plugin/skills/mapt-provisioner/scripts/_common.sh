#!/usr/bin/env bash
#
# Common helpers for mapt-provisioner scripts.
# Sourced by all scripts in this directory.
#
# Required environment variables (varies by operation):
#   MAPT_BACKEND_URL        - Pulumi state backend URL (always required)
#   AWS_PROFILE             - AWS profile (alternative to explicit keys, e.g. saml)
#   AWS_ACCESS_KEY_ID       - AWS credential (for AWS targets, if not using AWS_PROFILE)
#   AWS_SECRET_ACCESS_KEY   - AWS credential (for AWS targets, if not using AWS_PROFILE)
#   ARM_TENANT_ID           - Azure credential (for Azure targets; mapt maps ARM_* -> AZURE_* internally)
#   ARM_SUBSCRIPTION_ID     - Azure credential (for Azure targets)
#   ARM_CLIENT_ID           - Azure credential (for Azure targets)
#   ARM_CLIENT_SECRET       - Azure credential (for Azure targets)
#   AZURE_STORAGE_ACCOUNT        - Azure storage account name (for azblob state backend)
#   AZURE_STORAGE_KEY            - Azure storage account key (for azblob state backend)
#   PULL_SECRET_FILE             - Path to OpenShift pull secret (for SNC targets)

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure ~/.local/bin is on PATH (mapt install target)
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# Install mapt if not present — idempotent, skips immediately if already installed
"$SCRIPTS_DIR/../../../tools/mapt/install.sh" >/dev/null

# Set Pulumi passphrase if not already set (matches mapt Containerfile default)
export PULUMI_CONFIG_PASSPHRASE="${PULUMI_CONFIG_PASSPHRASE:-passphrase}"

# Default connection details output path
DEFAULT_CONN_DETAILS_OUTPUT="/tmp/mapt-conn-details"

require_arg() {
    local flag="$1"
    local value="${2:-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        echo "ERROR: $flag requires a value" >&2
        exit 1
    fi
}

validate_backend_url() {
    if [[ -z "${MAPT_BACKEND_URL:-}" ]]; then
        echo "ERROR: MAPT_BACKEND_URL is required but not set." >&2
        echo "  Set it to a persistent Pulumi state backend URL." >&2
        echo "  Examples:" >&2
        echo "    export MAPT_BACKEND_URL=s3://my-mapt-state" >&2
        echo "    export MAPT_BACKEND_URL=azblob://my-state-container" >&2
        echo "" >&2
        echo "  A persistent backend is required to avoid orphaning cloud resources." >&2
        echo "  Without it, if the container dies you lose the ability to destroy" >&2
        echo "  provisioned resources (VMs, GPUs, networking) which keep billing." >&2
        exit 1
    fi

    if [[ "${MAPT_BACKEND_URL}" == azblob://* ]]; then
        local missing=()
        [[ -z "${AZURE_STORAGE_ACCOUNT:-}" ]] && missing+=("AZURE_STORAGE_ACCOUNT")
        [[ -z "${AZURE_STORAGE_KEY:-}" ]] && missing+=("AZURE_STORAGE_KEY")
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "ERROR: azblob backend requires: ${missing[*]}" >&2
            exit 1
        fi
    fi
}

validate_aws_credentials() {
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        return 0
    fi
    local missing=()
    [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] && missing+=("AWS_ACCESS_KEY_ID")
    [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]] && missing+=("AWS_SECRET_ACCESS_KEY")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required AWS credentials." >&2
        echo "  Either set AWS_PROFILE (for profile-based auth):" >&2
        echo "    export AWS_PROFILE=saml" >&2
        echo "  Or set explicit credentials:" >&2
        echo "    export AWS_ACCESS_KEY_ID=..." >&2
        echo "    export AWS_SECRET_ACCESS_KEY=..." >&2
        exit 1
    fi
}

validate_azure_credentials() {
    local missing=()
    [[ -z "${ARM_TENANT_ID:-}" ]] && missing+=("ARM_TENANT_ID")
    [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]] && missing+=("ARM_SUBSCRIPTION_ID")
    [[ -z "${ARM_CLIENT_ID:-}" ]] && missing+=("ARM_CLIENT_ID")
    [[ -z "${ARM_CLIENT_SECRET:-}" ]] && missing+=("ARM_CLIENT_SECRET")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required Azure credentials: ${missing[*]}" >&2
        echo "  mapt reads ARM_* vars and maps them to AZURE_* internally." >&2
        exit 1
    fi
}

validate_provider_credentials() {
    local provider="$1"
    case "$provider" in
        aws)
            validate_aws_credentials
            ;;
        azure)
            validate_azure_credentials
            ;;
        *)
            echo "ERROR: Unknown provider '$provider'. Supported: aws, azure" >&2
            exit 1
            ;;
    esac
}

validate_pull_secret() {
    if [[ -z "${PULL_SECRET_FILE:-}" ]]; then
        echo "ERROR: PULL_SECRET_FILE is required but not set." >&2
        echo "  Download the pull secret from https://console.redhat.com/openshift/create/local" >&2
        echo "  Then: export PULL_SECRET_FILE=/path/to/pull-secret.json" >&2
        exit 1
    fi
    if [[ ! -f "$PULL_SECRET_FILE" ]]; then
        echo "ERROR: Pull secret file does not exist: $PULL_SECRET_FILE" >&2
        exit 1
    fi
}

generate_project_name() {
    local target="$1"
    echo "mapt-${target}-$(date +%Y%m%d-%H%M%S)-${RANDOM}"
}

log_connection_details() {
    local output_dir="$1"
    if [[ ! -d "$output_dir" ]]; then
        echo "WARNING: Connection details directory not found: $output_dir" >&2
        return 1
    fi
    echo "=== Connection Details ==="
    for f in "$output_dir"/*; do
        if [[ -f "$f" ]]; then
            echo "--- $(basename "$f") ---"
            cat "$f"
            echo ""
        fi
    done
}
