#!/usr/bin/env bash
#
# kubectl Installation Script (Linux Only)
#
# This script installs or updates kubectl on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install kubectl
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
# renovate: datasource=github-releases depName=kubernetes/kubernetes
KUBECTL_VERSION="1.35.3"

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

# Get installed kubectl version
get_kubectl_version() {
    if command_exists kubectl; then
        kubectl version --client -o json 2>/dev/null | grep -oP '"gitVersion":\s*"v\K[0-9.]+' || echo "unknown"
    else
        echo "not_installed"
    fi
}

# ============================================================================
# KUBECTL INSTALLATION
# ============================================================================

check_kubectl() {
    local current_version

    if ! command_exists kubectl; then
        log "kubectl is not installed"
        return 1
    fi

    current_version=$(get_kubectl_version)
    log "kubectl version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine kubectl version"
        return 0
    fi

    if version_gte "$current_version" "$KUBECTL_VERSION"; then
        log "kubectl is up to date (>= $KUBECTL_VERSION)"
        return 0
    else
        log "kubectl version $current_version is older than required $KUBECTL_VERSION"
        return 1
    fi
}

install_kubectl() {
    local arch
    arch=$(detect_arch)

    log "Installing kubectl v${KUBECTL_VERSION} for Linux $arch..."

    # Verify we're on Linux
    verify_linux || return 1

    # Ensure install directory exists
    mkdir -p "$INSTALL_DIR"

    # Download based on architecture
    local download_arch
    if [ "$arch" = "x86_64" ]; then
        download_arch="amd64"
    else
        download_arch="arm64"
    fi

    local download_url="https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${download_arch}/kubectl"

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "$INSTALL_DIR/kubectl"

    chmod +x "$INSTALL_DIR/kubectl"

    # Verify installation
    if check_kubectl; then
        log "kubectl installed successfully"
        return 0
    else
        log "kubectl installation verification failed" >&2
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
        check_kubectl
        exit $?
    fi

    # Install if needed
    if ! check_kubectl; then
        echo ""
        log "Installing kubectl..."
        install_kubectl
    fi
}

# Run main function
main "$@"
