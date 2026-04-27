#!/usr/bin/env bash
#
# kubectl-ka (KubeArchive CLI) Installation Script (Linux Only)
#
# This script installs or updates the kubectl-ka plugin on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install kubectl-ka
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
# renovate: datasource=github-releases depName=kubearchive/kubearchive
KUBECTL_KA_VERSION="1.21.3"

# ============================================================================
# CONFIGURATION
# ============================================================================

if [ -z "${INSTALL_DIR:-}" ]; then
    if [ -w "/usr/local/bin" ]; then
        INSTALL_DIR="/usr/local/bin"
    else
        INSTALL_DIR="$HOME/.local/bin"
    fi
fi

TMP_DIR="${TMP_DIR:-/tmp/kubectl-ka-install}"

# ============================================================================
# KUBECTL-KA INSTALLATION
# ============================================================================

check_kubectl_ka() {
    local current_version

    if ! command_exists kubectl-ka; then
        log "kubectl-ka is not installed"
        return 1
    fi

    current_version=$(kubectl-ka version 2>&1 | grep -oP 'kubectl-archive version v\K[0-9.]+' || echo "unknown")
    log "kubectl-ka version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine kubectl-ka version"
        return 0
    fi

    if version_gte "$current_version" "$KUBECTL_KA_VERSION"; then
        log "kubectl-ka is up to date (>= $KUBECTL_KA_VERSION)"
        return 0
    else
        log "kubectl-ka version $current_version is older than required $KUBECTL_KA_VERSION"
        return 1
    fi
}

install_kubectl_ka() {
    local arch
    arch=$(detect_arch)

    log "Installing kubectl-ka v${KUBECTL_KA_VERSION} for Linux $arch..."

    verify_linux || return 1

    mkdir -p "$TMP_DIR"

    local download_arch
    if [ "$arch" = "x86_64" ]; then
        download_arch="amd64"
    else
        download_arch="arm64"
    fi

    local download_url="https://github.com/kubearchive/kubearchive/releases/download/v${KUBECTL_KA_VERSION}/kubectl-ka-linux-${download_arch}"

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "${TMP_DIR}/kubectl-ka"
    chmod +x "${TMP_DIR}/kubectl-ka"

    log "Installing to: $INSTALL_DIR"
    mv "${TMP_DIR}/kubectl-ka" "$INSTALL_DIR/kubectl-ka"

    rm -rf "$TMP_DIR"

    if check_kubectl_ka; then
        log "✓ kubectl-ka installed successfully"
        return 0
    else
        log "✗ kubectl-ka installation verification failed" >&2
        return 1
    fi
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

main() {
    local check_only=false

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

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$TMP_DIR"

    warn_if_not_in_path "$INSTALL_DIR"

    if [ "$check_only" = true ]; then
        check_kubectl_ka
        exit $?
    fi

    if ! check_kubectl_ka; then
        echo ""
        log "Installing kubectl-ka..."
        install_kubectl_ka
    fi
}

main "$@"
