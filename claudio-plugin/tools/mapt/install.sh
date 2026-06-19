#!/usr/bin/env bash
#
# Mapt + Pulumi Installation Script (Linux Only)
#
# This script installs or updates mapt, the Pulumi CLI, and all required
# Pulumi provider plugins on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install mapt + pulumi + providers
#   ./install.sh --check        # Only check, don't install

set -euo pipefail

# ============================================================================
# LOAD COMMON LIBRARY
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

# ============================================================================
# DEPENDENCY VERSIONS
# ============================================================================

# renovate: datasource=github-releases depName=redhat-developer/mapt
MAPT_VERSION="0.14.2"

# renovate: datasource=github-releases depName=pulumi/pulumi
PULUMI_VERSION="3.234.0"

# Pulumi provider plugin versions (match mapt's oci/Containerfile)
# renovate: datasource=github-releases depName=pulumi/pulumi-aws
PULUMI_AWS_VERSION="7.28.0"
# renovate: datasource=github-releases depName=pulumi/pulumi-awsx
PULUMI_AWSX_VERSION="3.5.0"
# renovate: datasource=github-releases depName=pulumi/pulumi-azure-native
PULUMI_AZURE_NATIVE_VERSION="3.17.0"
# renovate: datasource=github-releases depName=pulumi/pulumi-command
PULUMI_COMMAND_VERSION="1.2.1"
# renovate: datasource=github-releases depName=pulumi/pulumi-tls
PULUMI_TLS_VERSION="5.3.1"
# renovate: datasource=github-releases depName=pulumi/pulumi-random
PULUMI_RANDOM_VERSION="4.19.2"
# renovate: datasource=github-releases depName=pulumi/pulumi-aws-native
PULUMI_AWS_NATIVE_VERSION="1.63.0"
# renovate: datasource=github-releases depName=pulumi/pulumi-gitlab
PULUMI_GITLAB_VERSION="9.11.0"

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

_created_tmp=false
if [ -z "${TMP_DIR:-}" ]; then
    TMP_DIR=$(mktemp -d)
    _created_tmp=true
fi

_cleanup_tmp() {
    [ "$_created_tmp" = true ] && rm -rf "$TMP_DIR"
}
trap _cleanup_tmp EXIT

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

get_pulumi_version() {
    if command_exists pulumi; then
        pulumi version 2>&1 | sed 's/^v//' || echo "unknown"
    else
        echo "not_installed"
    fi
}

# Map uname arch to pulumi download arch (pulumi uses x64, not x86_64)
pulumi_arch() {
    local arch
    arch=$(detect_arch)
    if [ "$arch" = "x86_64" ]; then
        echo "x64"
    else
        echo "arm64"
    fi
}

# Map uname arch to mapt release asset name
mapt_arch() {
    local arch
    arch=$(detect_arch)
    if [ "$arch" = "x86_64" ]; then
        echo "amd64"
    else
        echo "arm64"
    fi
}

# ============================================================================
# CHECK FUNCTIONS
# ============================================================================

check_mapt() {
    if ! command_exists mapt; then
        log "mapt is not installed"
        return 1
    fi
    local version_file="$INSTALL_DIR/mapt.version"
    if [[ ! -f "$version_file" ]]; then
        log "mapt version file missing, reinstalling"
        return 1
    fi
    local installed_version
    installed_version=$(cat "$version_file")
    if [[ "$installed_version" != "$MAPT_VERSION" ]]; then
        log "mapt version $installed_version does not match required $MAPT_VERSION"
        return 1
    fi
    log "mapt $installed_version is up to date"
    return 0
}

check_pulumi() {
    local current_version

    if ! command_exists pulumi; then
        log "pulumi is not installed"
        return 1
    fi

    current_version=$(get_pulumi_version)
    log "pulumi version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine pulumi version"
        return 1
    fi

    if version_gte "$current_version" "$PULUMI_VERSION"; then
        log "pulumi is up to date (>= $PULUMI_VERSION)"
        return 0
    else
        log "pulumi version $current_version is older than required $PULUMI_VERSION"
        return 1
    fi
}

check_pulumi_providers() {
    if ! command_exists pulumi; then
        log "pulumi not installed, cannot check providers"
        return 1
    fi

    local missing=()
    local installed
    installed=$(pulumi plugin ls 2>/dev/null || echo "")

    local -A providers=(
        ["aws"]="$PULUMI_AWS_VERSION"
        ["awsx"]="$PULUMI_AWSX_VERSION"
        ["azure-native"]="$PULUMI_AZURE_NATIVE_VERSION"
        ["command"]="$PULUMI_COMMAND_VERSION"
        ["tls"]="$PULUMI_TLS_VERSION"
        ["random"]="$PULUMI_RANDOM_VERSION"
        ["aws-native"]="$PULUMI_AWS_NATIVE_VERSION"
        ["gitlab"]="$PULUMI_GITLAB_VERSION"
    )

    for provider in "${!providers[@]}"; do
        local escaped_version="${providers[$provider]//./\\.}"
        if ! echo "$installed" | grep -qE "^${provider}[[:space:]]+resource[[:space:]]+${escaped_version}([[:space:]]|$)"; then
            missing+=("${provider} v${providers[$provider]}")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log "Missing pulumi providers: ${missing[*]}"
        return 1
    fi

    log "All pulumi providers are installed"
    return 0
}

check_all() {
    local failed=false

    if ! check_mapt; then failed=true; fi
    if ! check_pulumi; then failed=true; fi
    if ! check_pulumi_providers; then failed=true; fi

    if [ "$failed" = true ]; then
        return 1
    fi
    return 0
}

# ============================================================================
# INSTALL FUNCTIONS
# ============================================================================

install_mapt() {
    local arch
    arch=$(mapt_arch)

    log "Installing mapt v${MAPT_VERSION} for Linux $arch..."

    verify_linux || return 1
    mkdir -p "$TMP_DIR"

    local download_url="https://github.com/redhat-developer/mapt/releases/download/v${MAPT_VERSION}/mapt-linux-${arch}"
    local checksums_url="https://github.com/redhat-developer/mapt/releases/download/v${MAPT_VERSION}/mapt-checksums.txt"

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "${TMP_DIR}/mapt"
    curl -fsSL "$checksums_url" -o "${TMP_DIR}/mapt-checksums.txt"

    log "Verifying checksum..."
    local expected
    expected=$(grep "mapt-linux-${arch}" "${TMP_DIR}/mapt-checksums.txt" | awk '{print $1}')
    local actual
    actual=$(sha256sum "${TMP_DIR}/mapt" | awk '{print $1}')
    if [ "$expected" != "$actual" ]; then
        log "✗ Checksum mismatch for mapt-linux-${arch}" >&2
        log "  Expected: $expected" >&2
        log "  Actual:   $actual" >&2
        return 1
    fi
    log "✓ Checksum verified"

    chmod +x "${TMP_DIR}/mapt"

    log "Installing to: $INSTALL_DIR"
    if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
        maybe_sudo mv "${TMP_DIR}/mapt" "$INSTALL_DIR/mapt"
    else
        mv "${TMP_DIR}/mapt" "$INSTALL_DIR/mapt"
    fi

    echo "$MAPT_VERSION" > "$INSTALL_DIR/mapt.version"

    if check_mapt; then
        log "✓ mapt installed successfully"
        return 0
    else
        log "✗ mapt installation verification failed" >&2
        return 1
    fi
}

install_pulumi() {
    local arch
    arch=$(pulumi_arch)

    log "Installing pulumi v${PULUMI_VERSION} for Linux $arch..."

    verify_linux || return 1

    if ! command_exists tar; then
        log "ERROR: tar is required but not installed" >&2
        return 1
    fi

    mkdir -p "$TMP_DIR"
    pushd "$TMP_DIR" >/dev/null

    local download_url="https://github.com/pulumi/pulumi/releases/download/v${PULUMI_VERSION}/pulumi-v${PULUMI_VERSION}-linux-${arch}.tar.gz"
    local checksums_url="https://get.pulumi.com/releases/sdk/pulumi-${PULUMI_VERSION}-checksums.txt"

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "pulumi.tar.gz"
    curl -fsSL "$checksums_url" -o "pulumi-checksums.txt"

    log "Verifying checksum..."
    local filename="pulumi-v${PULUMI_VERSION}-linux-${arch}.tar.gz"
    local expected
    expected=$(grep "$filename" "pulumi-checksums.txt" | awk '{print $1}')
    local actual
    actual=$(sha256sum "pulumi.tar.gz" | awk '{print $1}')
    if [ "$expected" != "$actual" ]; then
        log "✗ Checksum mismatch for $filename" >&2
        log "  Expected: $expected" >&2
        log "  Actual:   $actual" >&2
        return 1
    fi
    log "✓ Checksum verified"

    log "Extracting..."
    tar -xzf "pulumi.tar.gz"

    log "Installing to: $INSTALL_DIR"
    if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
        maybe_sudo mv pulumi/pulumi "$INSTALL_DIR/pulumi"
    else
        mv pulumi/pulumi "$INSTALL_DIR/pulumi"
    fi

    popd >/dev/null

    if check_pulumi; then
        log "✓ pulumi installed successfully"
        return 0
    else
        log "✗ pulumi installation verification failed" >&2
        return 1
    fi
}

install_pulumi_providers() {
    log "Installing pulumi provider plugins..."

    pulumi plugin install --exact resource aws "$PULUMI_AWS_VERSION" \
        && pulumi plugin install --exact resource awsx "$PULUMI_AWSX_VERSION" \
        && pulumi plugin install --exact resource azure-native "$PULUMI_AZURE_NATIVE_VERSION" \
        && pulumi plugin install --exact resource command "$PULUMI_COMMAND_VERSION" \
        && pulumi plugin install --exact resource tls "$PULUMI_TLS_VERSION" \
        && pulumi plugin install --exact resource random "$PULUMI_RANDOM_VERSION" \
        && pulumi plugin install --exact resource aws-native "$PULUMI_AWS_NATIVE_VERSION" \
        && pulumi plugin install --exact resource gitlab "$PULUMI_GITLAB_VERSION"

    if check_pulumi_providers; then
        log "✓ All pulumi providers installed successfully"
        return 0
    else
        log "✗ Pulumi provider installation verification failed" >&2
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

    export PATH="$INSTALL_DIR:$PATH"
    warn_if_not_in_path "$INSTALL_DIR"

    if [ "$check_only" = true ]; then
        check_all
        exit $?
    fi

    if ! check_mapt; then
        echo ""
        log "Installing mapt..."
        install_mapt
    fi

    if ! check_pulumi; then
        echo ""
        log "Installing pulumi..."
        install_pulumi
    fi

    if ! check_pulumi_providers; then
        echo ""
        log "Installing pulumi providers..."
        install_pulumi_providers
    fi

    log ""
    log "✓ All mapt dependencies installed successfully"
}

main "$@"
