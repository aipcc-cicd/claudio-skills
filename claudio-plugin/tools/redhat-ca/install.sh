#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

CERT_URL="https://certs.corp.redhat.com/certs/Current-IT-Root-CAs.pem"
CERT_SHA256="e9713aed04b4ef3003edd10fc9c4f8ab875436e4a44195f0cbafcdf95e9bad2c"
CERT_FILE="redhat-it-root-cas.pem"
ANCHOR_DIR="/etc/pki/ca-trust/source/anchors"

check_cert() {
    if [ -f "$ANCHOR_DIR/$CERT_FILE" ]; then
        local existing_sha
        existing_sha=$(sha256sum "$ANCHOR_DIR/$CERT_FILE" 2>/dev/null | cut -d' ' -f1)
        if [ "$existing_sha" = "$CERT_SHA256" ]; then
            log "Red Hat IT Root CA is already installed"
            return 0
        fi
        log "Installed Red Hat IT Root CA does not match the pinned hash — reinstalling"
        return 1
    fi
    log "Red Hat IT Root CA is not installed"
    return 1
}

install_cert() {
    verify_linux || return 1

    if [ "$EUID" -ne 0 ]; then
        log "ERROR: Must run as root or via sudo" >&2
        return 1
    fi

    if [ ! -d "$ANCHOR_DIR" ]; then
        log "ERROR: $ANCHOR_DIR does not exist — is this a RHEL/UBI system?" >&2
        return 1
    fi

    local tmp_cert
    tmp_cert=$(mktemp /tmp/redhat-ca-XXXXXX.pem)
    trap 'rm -f "$tmp_cert"' RETURN

    log "Downloading Red Hat IT Root CA from $CERT_URL..."
    if ! curl -ksS --fail --connect-timeout 10 --max-time 30 "$CERT_URL" -o "$tmp_cert"; then
        log "WARNING: Could not download Red Hat IT Root CA — host may not be reachable" >&2
        return 1
    fi

    if ! grep -q "BEGIN CERTIFICATE" "$tmp_cert"; then
        log "ERROR: Downloaded file is not a valid PEM certificate" >&2
        return 1
    fi

    local actual_sha
    actual_sha=$(sha256sum "$tmp_cert" | cut -d' ' -f1)
    if [ "$actual_sha" != "$CERT_SHA256" ]; then
        log "ERROR: Certificate hash mismatch (expected $CERT_SHA256, got $actual_sha)" >&2
        return 1
    fi

    mv "$tmp_cert" "$ANCHOR_DIR/$CERT_FILE"

    if ! command_exists update-ca-trust; then
        log "ERROR: update-ca-trust not found" >&2
        rm -f "$ANCHOR_DIR/$CERT_FILE"
        return 1
    fi

    if ! update-ca-trust; then
        log "ERROR: Failed to update the system trust store" >&2
        rm -f "$ANCHOR_DIR/$CERT_FILE"
        return 1
    fi
    log "✓ Red Hat IT Root CA installed and trust store updated"
}

main() {
    if [ "${1:-}" = "--check" ] || [ "${1:-}" = "-c" ]; then
        check_cert
        exit $?
    fi

    if ! check_cert; then
        install_cert
    fi
}

main "$@"
