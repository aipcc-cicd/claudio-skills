#!/usr/bin/env bash
#
# Python Dependencies Installation Script (Linux Only)
#
# This script ensures python3 and pip3 are available, then installs
# pip requirements from any *-requirements.txt files found in the
# same directory as this script.
#
# Usage:
#   ./install.sh                # Install Python dependencies
#   ./install.sh --check        # Only check, don't install

set -euo pipefail

# ============================================================================
# LOAD COMMON LIBRARY
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

# ============================================================================
# PYTHON CHECKS
# ============================================================================

check_python() {
    if ! command_exists python3; then
        log "python3 is not installed"
        return 1
    fi

    local python_version
    python_version=$(python3 --version 2>&1 | grep -oP 'Python \K[0-9.]+' || echo "unknown")
    log "python3 version: $python_version"
    return 0
}

check_pip() {
    if ! command_exists pip3; then
        log "pip3 is not installed"
        return 1
    fi

    local pip_version
    pip_version=$(pip3 --version 2>&1 | grep -oP 'pip \K[0-9.]+' || echo "unknown")
    log "pip3 version: $pip_version"
    return 0
}

# ============================================================================
# INSTALLATION
# ============================================================================

install_pip() {
    log "Installing python3-pip via dnf..."

    verify_linux || return 1

    if command_exists dnf; then
        dnf install -y python3-pip
    else
        log "ERROR: dnf not found — cannot install python3-pip" >&2
        return 1
    fi

    if check_pip; then
        log "✓ pip3 installed successfully"
        return 0
    else
        log "✗ pip3 installation failed" >&2
        return 1
    fi
}

install_requirements() {
    local req_files=()

    # Find all *-requirements.txt files in the script directory
    for f in "$SCRIPT_DIR"/*-requirements.txt; do
        [ -f "$f" ] && req_files+=("$f")
    done

    if [ ${#req_files[@]} -eq 0 ]; then
        log "No *-requirements.txt files found in $SCRIPT_DIR"
        return 0
    fi

    for req_file in "${req_files[@]}"; do
        log "Installing requirements from: $(basename "$req_file")"
        pip3 install --no-cache-dir -r "$req_file"
    done

    log "✓ Python requirements installed successfully"
    return 0
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

    # Check python3
    if ! check_python; then
        log "ERROR: python3 is required but not installed" >&2
        exit 1
    fi

    # Execute based on options
    if [ "$check_only" = true ]; then
        check_pip
        exit $?
    fi

    # Install pip if needed
    if ! check_pip; then
        echo ""
        log "Installing pip3..."
        install_pip
    fi

    # Install requirements
    install_requirements
}

# Run main function
main "$@"
