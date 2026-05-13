#!/usr/bin/env bash
#
# Read the text content of a Google Slides presentation.
#
# Usage:
#   ./read_slide.sh <presentation-id> [OPTIONS]
#
# Options:
#   --human     Print content slide-by-slide (default: JSON)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "ERROR: Missing required argument: presentation-id" >&2
    echo "Usage: $(basename "$0") <presentation-id> [--human]" >&2
    exit 1
fi

PRES_ID="$1"
shift

HUMAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --human) HUMAN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

echo "Fetching presentation: $PRES_ID" >&2

RAW=$(gws slides presentations get \
    --params "$(jq -n --arg id "$PRES_ID" '{presentationId: $id}')")

TITLE=$(echo "$RAW" | jq -r '.title // "unknown"')
SLIDE_COUNT=$(echo "$RAW" | jq '.slides | length')
WEB_LINK="https://docs.google.com/presentation/d/${PRES_ID}/edit"

echo "Title: $TITLE ($SLIDE_COUNT slides)" >&2

# Extract text from all slides — walks pageElements recursively for text runs
SLIDES_TEXT=$(echo "$RAW" | jq '[
  .slides[]? |
  {
    objectId,
    elements: [
      .pageElements[]? |
      select(.shape.text != null) |
      {
        type: (.shape.placeholder.type // "FREEFORM"),
        text: (
          [.shape.text.textElements[]? |
           select(.textRun != null) |
           .textRun.content] |
          join("") | gsub(""; "\n") | rtrimstr("\n")
        )
      } |
      select(.text != "")
    ]
  }
]')

if [ "$HUMAN" = true ]; then
    echo ""
    echo "=== $TITLE ==="
    echo "ID:     $PRES_ID"
    echo "Slides: $SLIDE_COUNT"
    echo "Link:   $WEB_LINK"
    echo ""
    echo "$SLIDES_TEXT" | jq -r 'to_entries[] | "--- Slide \(.key + 1) ---\n" + (.value.elements[] | "[\(.type)] \(.text)")'
else
    jq -n \
        --arg id "$PRES_ID" \
        --arg title "$TITLE" \
        --argjson count "$SLIDE_COUNT" \
        --arg link "$WEB_LINK" \
        --argjson slides "$SLIDES_TEXT" \
        '{id: $id, title: $title, slideCount: $count, webViewLink: $link, slides: $slides}'
fi
