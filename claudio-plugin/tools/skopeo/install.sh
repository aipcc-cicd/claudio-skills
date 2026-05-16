#!/usr/bin/env bash
#
# Skopeo Installation Script (Linux Only)
#
# This script installs skopeo using the system package manager.
# Supports: RHEL, Fedora (dnf), Ubuntu/Debian (apt), Alpine (apk)
#
# Usage:
#   ./install.sh                # Check and install skopeo
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
# Skopeo is primarily installed in the claudio container (ubi10) via microdnf;
# this script is a fallback for environments where skopeo is not pre-installed.
# renovate: datasource=repology depName=centos_stream_10/skopeo versioning=loose
SKOPEO_VERSION="1.22.2"

# ============================================================================
# SKOPEO INSTALLATION
# ============================================================================

check_skopeo() {
    if ! command_exists skopeo; then
        log "skopeo is not installed"
        return 1
    fi

    local current_version
    current_version=$(skopeo --version 2>&1 | grep -oP 'skopeo version \K[0-9.]+' || echo "unknown")
    log "skopeo version: $current_version"
    return 0
}

detect_package_manager() {
    if command_exists dnf; then
        echo "dnf"
    elif command_exists apt-get; then
        echo "apt"
    elif command_exists apk; then
        echo "apk"
    else
        echo "unknown"
    fi
}

install_skopeo() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)

    log "Installing skopeo ${SKOPEO_VERSION} using package manager: $pkg_manager"

    # Verify we're on Linux
    verify_linux || return 1

    case "$pkg_manager" in
        dnf)
            log "Installing skopeo via dnf..."
            if maybe_sudo dnf install -y "skopeo-${SKOPEO_VERSION}" 2>/dev/null || maybe_sudo dnf install -y skopeo; then
                log "✓ skopeo installed successfully via dnf"
            else
                log "✗ Failed to install skopeo via dnf" >&2
                log "Please install manually: dnf install skopeo" >&2
                return 1
            fi
            ;;
        apt)
            log "Installing skopeo via apt..."
            if maybe_sudo apt-get update && { maybe_sudo apt-get install -y "skopeo=${SKOPEO_VERSION}*" 2>/dev/null || maybe_sudo apt-get install -y skopeo; }; then
                log "✓ skopeo installed successfully via apt"
            else
                log "✗ Failed to install skopeo via apt" >&2
                log "Please install manually: apt-get install skopeo" >&2
                return 1
            fi
            ;;
        apk)
            log "Installing skopeo via apk..."
            if maybe_sudo apk add "skopeo~=${SKOPEO_VERSION}" 2>/dev/null || maybe_sudo apk add skopeo; then
                log "✓ skopeo installed successfully via apk"
            else
                log "✗ Failed to install skopeo via apk" >&2
                log "Please install manually: apk add skopeo" >&2
                return 1
            fi
            ;;
        *)
            log "✗ No supported package manager found (dnf, apt, or apk required)" >&2
            log "" >&2
            log "Please install skopeo manually using your distribution's package manager:" >&2
            log "  - RHEL/Fedora: dnf install skopeo" >&2
            log "  - Ubuntu/Debian: apt-get install skopeo" >&2
            log "  - Alpine: apk add skopeo" >&2
            log "  - Arch: pacman -S skopeo" >&2
            log "" >&2
            log "See: https://github.com/containers/skopeo/blob/main/install.md" >&2
            return 1
            ;;
    esac

    # Verify installation
    if check_skopeo; then
        return 0
    else
        log "✗ skopeo installation verification failed" >&2
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

    # Execute based on options
    if [ "$check_only" = true ]; then
        check_skopeo
        exit $?
    fi

    # Install if needed
    if ! check_skopeo; then
        echo ""
        log "Installing skopeo..."
        install_skopeo
    fi
}

# Run main function
main "$@"
