#!/usr/bin/env bash
#
# uv Installation Script (Linux Only)
#
# This script installs or updates the uv Python package manager on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install uv
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
# renovate: datasource=github-releases depName=astral-sh/uv
UV_VERSION="0.11.16"

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

TMP_DIR="${TMP_DIR:-/tmp/uv-install}"

# ============================================================================
# UV INSTALLATION
# ============================================================================

check_uv() {
    local current_version

    if ! command_exists uv; then
        log "uv is not installed"
        return 1
    fi

    current_version=$(uv --version 2>&1 | grep -oP 'uv \K[0-9.]+' || echo "unknown")
    log "uv version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine uv version"
        return 0
    fi

    if version_gte "$current_version" "$UV_VERSION"; then
        log "uv is up to date (>= $UV_VERSION)"
        return 0
    else
        log "uv version $current_version is older than required $UV_VERSION"
        return 1
    fi
}

install_uv() {
    local arch
    arch=$(detect_arch)

    log "Installing uv v${UV_VERSION} for Linux $arch..."

    # Verify we're on Linux
    verify_linux || return 1

    # Create temporary directory
    mkdir -p "$TMP_DIR"

    # Download based on architecture
    local download_arch
    if [ "$arch" = "x86_64" ]; then
        download_arch="x86_64-unknown-linux-gnu"
    else
        download_arch="aarch64-unknown-linux-gnu"
    fi

    local archive_name="uv-${download_arch}.tar.gz"
    local download_url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${archive_name}"

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "${TMP_DIR}/${archive_name}"

    log "Extracting..."
    tar -xzf "${TMP_DIR}/${archive_name}" -C "$TMP_DIR"

    # Install uv and uvx to INSTALL_DIR
    log "Installing to: $INSTALL_DIR"
    mv "${TMP_DIR}/uv-${download_arch}/uv" "$INSTALL_DIR/uv"
    mv "${TMP_DIR}/uv-${download_arch}/uvx" "$INSTALL_DIR/uvx"
    chmod +x "$INSTALL_DIR/uv" "$INSTALL_DIR/uvx"

    # Cleanup
    rm -rf "$TMP_DIR"

    # Verify installation
    if check_uv; then
        log "uv installed successfully"
        return 0
    else
        log "uv installation verification failed" >&2
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
        check_uv
        exit $?
    fi

    # Install if needed
    if ! check_uv; then
        echo ""
        log "Installing uv..."
        install_uv
    fi
}

# Run main function
main "$@"
