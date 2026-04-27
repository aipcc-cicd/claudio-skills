#!/usr/bin/env bash
#
# AWS CLI Installation Script (Linux Only)
#
# This script installs or updates the AWS CLI tool on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install AWS CLI
#   ./install.sh --check        # Only check, don't install

set -euo pipefail

# ============================================================================
# LOAD COMMON LIBRARY
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

# ============================================================================
# DEPENDENCY VERSION
# ============================================================================
# This version is tracked by Renovate for automatic updates
# renovate: datasource=github-tags depName=aws/aws-cli
AWS_CLI_VERSION="2.34.38"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Determine install directory - prefer /usr/local/bin, fallback to ~/.local/bin
if [ -z "${INSTALL_DIR:-}" ]; then
    if [ -w "/usr/local/bin" ]; then
        INSTALL_DIR="/usr/local/bin"
    else
        INSTALL_DIR="$HOME/.local/bin"
    fi
fi

TMP_DIR="${TMP_DIR:-/tmp/aws-cli-install}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get installed AWS CLI version
get_aws_cli_version() {
    if command_exists aws; then
        aws --version 2>&1 | grep -oP 'aws-cli/\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown"
    else
        echo "not_installed"
    fi
}

# ============================================================================
# AWS CLI INSTALLATION
# ============================================================================

check_aws_cli() {
    local current_version
    current_version=$(get_aws_cli_version)

    if [ "$current_version" = "not_installed" ]; then
        log "AWS CLI is not installed"
        return 1
    fi

    log "AWS CLI version: $current_version"

    if version_gte "$current_version" "$AWS_CLI_VERSION"; then
        log "AWS CLI is up to date (>= $AWS_CLI_VERSION)"
        return 0
    else
        log "AWS CLI version $current_version is older than required $AWS_CLI_VERSION"
        return 1
    fi
}

install_aws_cli() {
    local arch
    arch=$(detect_arch)

    log "Installing AWS CLI v${AWS_CLI_VERSION} for Linux $arch..."

    # Verify we're on Linux
    verify_linux || return 1

    # Check for unzip
    if ! command_exists unzip; then
        log "ERROR: unzip is required but not installed" >&2
        log "Please install unzip first (e.g., apt-get install unzip or yum install unzip)" >&2
        return 1
    fi

    # Create temporary directory
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"

    # Download based on architecture
    local download_url
    if [ "$arch" = "x86_64" ]; then
        download_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    else
        download_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
    fi

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "awscliv2.zip"

    log "Extracting..."
    unzip -q awscliv2.zip

    # Install based on determined INSTALL_DIR
    log "Installing to: $INSTALL_DIR"
    if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
        ./aws/install --update
    else
        ./aws/install --install-dir "$HOME/.local/aws-cli" --bin-dir "$INSTALL_DIR" --update
    fi

    # Cleanup
    cd - >/dev/null
    rm -rf "$TMP_DIR"

    # Verify installation
    if check_aws_cli; then
        log "✓ AWS CLI installed successfully"
        return 0
    else
        log "✗ AWS CLI installation verification failed" >&2
        return 1
    fi
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

main() {
    local check_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--check)
                check_only=true
                shift
                ;;
            *)
                log "ERROR: Unknown option: $1" >&2
                log "Usage: $(basename "$0") [--check]" >&2
                exit 1
                ;;
        esac
    done

    # Ensure INSTALL_DIR and TMP_DIR exist
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$TMP_DIR"

    # Check if INSTALL_DIR is in PATH
    warn_if_not_in_path "$INSTALL_DIR"

    # Execute based on options
    if [ "$check_only" = true ]; then
        check_aws_cli
        exit $?
    fi

    # Install if needed
    if ! check_aws_cli; then
        echo ""
        log "Installing AWS CLI..."
        install_aws_cli
    fi
}

# Run main function
main "$@"
