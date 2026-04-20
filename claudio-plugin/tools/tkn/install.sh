#!/usr/bin/env bash
#
# tkn (Tekton CLI) Installation Script (Linux Only)
#
# This script installs or updates tkn on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install tkn
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
# renovate: datasource=github-releases depName=tektoncd/cli
TKN_VERSION="0.40.0"

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

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get installed tkn version
get_tkn_version() {
    if command_exists tkn; then
        tkn version 2>/dev/null | grep -oP 'Client version:\s*\K[0-9.]+' || echo "unknown"
    else
        echo "not_installed"
    fi
}

# ============================================================================
# TKN INSTALLATION
# ============================================================================

check_tkn() {
    local current_version

    if ! command_exists tkn; then
        log "tkn is not installed"
        return 1
    fi

    current_version=$(get_tkn_version)
    log "tkn version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine tkn version"
        return 0
    fi

    if version_gte "$current_version" "$TKN_VERSION"; then
        log "tkn is up to date (>= $TKN_VERSION)"
        return 0
    else
        log "tkn version $current_version is older than required $TKN_VERSION"
        return 1
    fi
}

install_tkn() {
    local arch
    arch=$(detect_arch)

    log "Installing tkn v${TKN_VERSION} for Linux $arch..."

    # Verify we're on Linux
    verify_linux || return 1

    # Ensure install directory exists
    mkdir -p "$INSTALL_DIR"

    # Map architecture to download name
    local download_arch
    if [ "$arch" = "x86_64" ]; then
        download_arch="x86_64"
    else
        download_arch="aarch64"
    fi

    local tarball="tkn_${TKN_VERSION}_Linux_${download_arch}.tar.gz"
    local download_url="https://github.com/tektoncd/cli/releases/download/v${TKN_VERSION}/${tarball}"

    log "Downloading from: $download_url"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT

    curl -fsSL "$download_url" -o "$tmp_dir/$tarball"
    tar -xzf "$tmp_dir/$tarball" -C "$tmp_dir"
    mv "$tmp_dir/tkn" "$INSTALL_DIR/tkn"
    chmod +x "$INSTALL_DIR/tkn"

    # Verify installation
    if check_tkn; then
        log "tkn installed successfully"
        return 0
    else
        log "tkn installation verification failed" >&2
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

    # Ensure INSTALL_DIR exists
    mkdir -p "$INSTALL_DIR"

    # Check if INSTALL_DIR is in PATH
    warn_if_not_in_path "$INSTALL_DIR"

    # Execute based on options
    if [ "$check_only" = true ]; then
        check_tkn
        exit $?
    fi

    # Install if needed
    if ! check_tkn; then
        echo ""
        log "Installing tkn..."
        install_tkn
    fi
}

# Run main function
main "$@"
