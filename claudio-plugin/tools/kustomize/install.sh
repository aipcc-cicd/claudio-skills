#!/usr/bin/env bash
#
# kustomize Installation Script (Linux Only)
#
# This script installs or updates the kustomize Kubernetes configuration
# customization tool on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install kustomize
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
# Pinned to match KRD — bump manually when KRD bumps
KUSTOMIZE_VERSION="5.7.1"

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

TMP_DIR="${TMP_DIR:-/tmp/kustomize-install}"

# ============================================================================
# KUSTOMIZE INSTALLATION
# ============================================================================

check_kustomize() {
    local current_version

    if ! command_exists kustomize; then
        log "kustomize is not installed"
        return 1
    fi

    current_version=$(kustomize version 2>&1 | grep -oP 'v?\K[0-9.]+' || echo "unknown")
    log "kustomize version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine kustomize version"
        return 0
    fi

    if version_gte "$current_version" "$KUSTOMIZE_VERSION"; then
        log "kustomize is up to date (>= $KUSTOMIZE_VERSION)"
        return 0
    else
        log "kustomize version $current_version is older than required $KUSTOMIZE_VERSION"
        return 1
    fi
}

install_kustomize() {
    local arch
    arch=$(detect_arch)

    log "Installing kustomize v${KUSTOMIZE_VERSION} for Linux $arch..."

    # Verify we're on Linux
    verify_linux || return 1

    # Create temporary directory
    mkdir -p "$TMP_DIR"

    # Download based on architecture
    local download_arch
    if [ "$arch" = "x86_64" ]; then
        download_arch="amd64"
    else
        download_arch="arm64"
    fi

    local archive_name="kustomize_v${KUSTOMIZE_VERSION}_linux_${download_arch}.tar.gz"
    local download_url="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/${archive_name}"

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "${TMP_DIR}/${archive_name}"

    log "Extracting..."
    tar -xzf "${TMP_DIR}/${archive_name}" -C "$TMP_DIR"

    # Install to INSTALL_DIR
    log "Installing to: $INSTALL_DIR"
    mv "${TMP_DIR}/kustomize" "$INSTALL_DIR/kustomize"
    chmod +x "$INSTALL_DIR/kustomize"

    # Cleanup
    rm -rf "$TMP_DIR"

    # Verify installation
    if check_kustomize; then
        log "kustomize installed successfully"
        return 0
    else
        log "kustomize installation verification failed" >&2
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
        check_kustomize
        exit $?
    fi

    # Install if needed
    if ! check_kustomize; then
        echo ""
        log "Installing kustomize..."
        install_kustomize
    fi
}

# Run main function
main "$@"
