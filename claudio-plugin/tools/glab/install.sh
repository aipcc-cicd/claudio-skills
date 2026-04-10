#!/usr/bin/env bash
#
# glab Installation Script (Linux Only)
#
# This script installs or updates the glab GitLab CLI tool on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install glab
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
# renovate: datasource=gitlab-releases depName=gitlab-org/cli registryUrl=https://gitlab.com
GLAB_VERSION="1.92.1"

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

TMP_DIR="${TMP_DIR:-/tmp/glab-install}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get installed glab version
get_glab_version() {
    if command_exists glab; then
        glab version 2>&1 | grep -oP 'glab version \K[0-9.]+' || echo "unknown"
    else
        echo "not_installed"
    fi
}

# ============================================================================
# GLAB INSTALLATION
# ============================================================================

check_glab() {
    local current_version

    if ! command_exists glab; then
        log "glab is not installed"
        return 1
    fi

    current_version=$(get_glab_version)
    log "glab version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine glab version"
        return 0
    fi

    if version_gte "$current_version" "$GLAB_VERSION"; then
        log "glab is up to date (>= $GLAB_VERSION)"
        return 0
    else
        log "glab version $current_version is older than required $GLAB_VERSION"
        return 1
    fi
}

install_glab() {
    local arch
    arch=$(detect_arch)

    log "Installing glab v${GLAB_VERSION} for Linux $arch..."

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
    local download_url
    local archive_name
    if [ "$arch" = "x86_64" ]; then
        archive_name="glab_${GLAB_VERSION}_linux_amd64.tar.gz"
        download_url="https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/${archive_name}"
    else
        archive_name="glab_${GLAB_VERSION}_linux_arm64.tar.gz"
        download_url="https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/${archive_name}"  
    fi

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "$archive_name"

    log "Extracting..."
    tar -xzf "$archive_name"

    # Install to INSTALL_DIR
    log "Installing to: $INSTALL_DIR"

    # The extracted directory contains the glab binary in bin/ subdirectory
    if [ -f "bin/glab" ]; then
        chmod +x "bin/glab"
        mv "bin/glab" "$INSTALL_DIR/glab"
    elif [ -f "glab" ]; then
        # Fallback in case structure changes
        chmod +x "glab"
        mv "glab" "$INSTALL_DIR/glab"
    else
        log "ERROR: Could not find glab binary in extracted archive" >&2
        cd - >/dev/null
        rm -rf "$TMP_DIR"
        return 1
    fi

    # Cleanup
    cd - >/dev/null
    rm -rf "$TMP_DIR"

    # Verify installation
    if check_glab; then
        log "✓ glab installed successfully"

        # Remove default config file to allow ENV-based authentication
        local config_path="$HOME/.config/glab-cli"
        local config_file="$config_path/config.yml"
        
        if [ -f "$config_file" ]; then
            log "Removing default config file: $config_file"
            rm -rf "$config_path"
            log "Config file removed - will use environment variables for authentication"
        fi

        return 0
    else
        log "✗ glab installation verification failed" >&2
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
        check_glab
        exit $?
    fi

    # Install if needed
    if ! check_glab; then
        echo ""
        log "Installing glab..."
        install_glab
    fi
}

# Run main function
main "$@"
