#!/usr/bin/env bash
#
# Create a Google Slides presentation from a JSON content file.
#
# Usage:
#   ./create_presentation.sh --title "Title" --content /path/to/content.json [--human]
#
# See create_presentation.py for content JSON format.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/create_presentation.py" "$@"
