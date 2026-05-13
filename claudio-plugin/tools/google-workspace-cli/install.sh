#!/usr/bin/env bash
#
# Google Workspace CLI (gws) Installation Script (Linux Only)
#
# This script installs or updates the gws Google Workspace CLI tool on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install gws
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
# renovate: datasource=github-releases depName=googleworkspace/cli
GWS_VERSION="0.22.5"

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

TMP_DIR="${TMP_DIR:-/tmp/gws-install}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get installed gws version
get_gws_version() {
    if command_exists gws; then
        gws --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown"
    else
        echo "not_installed"
    fi
}

# ============================================================================
# GWS INSTALLATION
# ============================================================================

check_gws() {
    local current_version

    if ! command_exists gws; then
        log "gws is not installed"
        return 1
    fi

    current_version=$(get_gws_version)
    log "gws version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine gws version, triggering reinstall"
        return 1
    fi

    if version_gte "$current_version" "$GWS_VERSION"; then
        log "gws is up to date (>= $GWS_VERSION)"
        return 0
    else
        log "gws version $current_version is older than required $GWS_VERSION"
        return 1
    fi
}

install_gws() {
    local arch
    arch=$(detect_arch)

    log "Installing gws v${GWS_VERSION} for Linux $arch..."

    # Verify we're on Linux
    verify_linux || return 1

    # Check for tar
    if ! command_exists tar; then
        log "ERROR: tar is required but not installed" >&2
        log "Please install tar first (e.g., apt-get install tar or yum install tar)" >&2
        return 1
    fi

    # Create temporary directory
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"

    # Download based on architecture
    local archive_name
    if [ "$arch" = "x86_64" ]; then
        archive_name="google-workspace-cli-x86_64-unknown-linux-gnu.tar.gz"
    else
        archive_name="google-workspace-cli-aarch64-unknown-linux-gnu.tar.gz"
    fi
    local download_url="https://github.com/googleworkspace/cli/releases/download/v${GWS_VERSION}/${archive_name}"

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "$archive_name"

    log "Extracting..."
    tar -xzf "$archive_name"

    # Install to INSTALL_DIR - handle different archive structures
    log "Installing to: $INSTALL_DIR"
    local binary_path
    if [ -f "gws" ]; then
        binary_path="gws"
    elif [ -f "bin/gws" ]; then
        binary_path="bin/gws"
    else
        binary_path=$(find . -name "gws" -type f | head -1)
        if [ -z "$binary_path" ]; then
            log "ERROR: Could not find gws binary in extracted archive" >&2
            cd - >/dev/null
            rm -rf "$TMP_DIR"
            return 1
        fi
    fi

    chmod +x "$binary_path"
    maybe_sudo mv "$binary_path" "$INSTALL_DIR/gws"

    # Cleanup
    cd - >/dev/null
    rm -rf "$TMP_DIR"

    # Verify installation
    if check_gws; then
        log "✓ gws installed successfully"
        return 0
    else
        log "✗ gws installation verification failed" >&2
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
        check_gws
        exit $?
    fi

    # Install if needed
    if ! check_gws; then
        echo ""
        log "Installing gws..."
        install_gws
    fi
}

# Run main function
main "$@"
