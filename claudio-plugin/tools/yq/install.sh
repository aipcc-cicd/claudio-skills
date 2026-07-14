#!/usr/bin/env bash
#
# yq Installation Script (Linux Only)
#
# This script installs or updates the yq YAML processor tool on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install yq
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
# renovate: datasource=github-releases depName=mikefarah/yq
YQ_VERSION="4.53.3"

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

TMP_DIR="${TMP_DIR:-/tmp/yq-install}"

# ============================================================================
# YQ INSTALLATION
# ============================================================================

check_yq() {
    local current_version

    if ! command_exists yq; then
        log "yq is not installed"
        return 1
    fi

    current_version=$(yq --version 2>&1 | grep -oP 'version v\K[0-9.]+' || echo "unknown")
    log "yq version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine yq version"
        return 0
    fi

    if version_gte "$current_version" "$YQ_VERSION"; then
        log "yq is up to date (>= $YQ_VERSION)"
        return 0
    else
        log "yq version $current_version is older than required $YQ_VERSION"
        return 1
    fi
}

install_yq() {
    local arch
    arch=$(detect_arch)

    log "Installing yq v${YQ_VERSION} for Linux $arch..."

    # Verify we're on Linux
    verify_linux || return 1

    # Create temporary directory
    mkdir -p "$TMP_DIR"

    # Download based on architecture
    local download_url
    if [ "$arch" = "x86_64" ]; then
        download_url="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64"
    else
        download_url="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_arm64"
    fi

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "${TMP_DIR}/yq"
    chmod +x "${TMP_DIR}/yq"

    # Install to INSTALL_DIR
    log "Installing to: $INSTALL_DIR"
    mv "${TMP_DIR}/yq" "$INSTALL_DIR/yq"

    # Cleanup
    rm -rf "$TMP_DIR"

    # Verify installation
    if check_yq; then
        log "✓ yq installed successfully"
        return 0
    else
        log "✗ yq installation verification failed" >&2
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
        check_yq
        exit $?
    fi

    # Install if needed
    if ! check_yq; then
        echo ""
        log "Installing yq..."
        install_yq
    fi
}

# Run main function
main "$@"
