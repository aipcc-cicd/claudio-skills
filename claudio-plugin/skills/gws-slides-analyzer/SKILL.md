---
name: gws-slides-analyzer
description: Search, read, create, and add diagrams to Google Slides presentations. Use when the user asks to find a presentation, read slide content, create a new Google Slides deck, or add visual diagrams to existing slides. Uses the Google Workspace CLI (gws). Requires prior authentication via `gws auth login` or a service account credential file.
allowed-tools: Bash(gws slides:*),Bash(gws drive files list:*),Bash(gws drive files get:*),Bash(gws auth:*),Bash(/output/gws-slides-analyzer/scripts/*.sh:*),Bash(/output/gws-slides-analyzer/scripts/*.py:*)
---

# Google Slides Analyzer

## Overview

Search, read, create, and add visual diagrams to Google Slides presentations using the [Google Workspace CLI](https://github.com/googleworkspace/cli) (`gws`).

**Prerequisites:**
- `gws` command is available and in PATH
- User is already authenticated (`gws auth login` or service account)
- `jq` for JSON parsing
- `python3` for presentation creation and diagrams

## Authentication

| Method | How to set up |
|--------|--------------|
| Interactive OAuth | `gws auth login` — browser-based consent flow |
| Service Account | Set `GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/path/to/sa.json` |
| Pre-obtained token | Set `GOOGLE_WORKSPACE_CLI_TOKEN=<token>` |

## Available Scripts

### `search_slides.sh`

Search for Google Slides presentations by name or content.

**Usage:**
```bash
/output/gws-slides-analyzer/scripts/search_slides.sh <query> [OPTIONS]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--limit N` | `20` | Maximum results |
| `--human` | — | Human-readable table output |

**Examples:**
```bash
/output/gws-slides-analyzer/scripts/search_slides.sh "quarterly review"
/output/gws-slides-analyzer/scripts/search_slides.sh "portfolio" --limit 5 --human
```

---

### `read_slide.sh`

Read the text content of a Google Slides presentation.

**Usage:**
```bash
/output/gws-slides-analyzer/scripts/read_slide.sh <presentation-id> [OPTIONS]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--human` | — | Print slide content in readable format |

**Examples:**
```bash
/output/gws-slides-analyzer/scripts/read_slide.sh <presentation-id>
/output/gws-slides-analyzer/scripts/read_slide.sh <presentation-id> --human
```

---

### `create_presentation.sh`

Create a new Google Slides presentation, or overwrite an existing one, from a JSON content file.

**Usage:**
```bash
# Create new
/output/gws-slides-analyzer/scripts/create_presentation.sh \
  --title "My Deck" --content /path/to/content.json [--human]

# Overwrite existing
/output/gws-slides-analyzer/scripts/create_presentation.sh \
  --presentation-id <id> --content /path/to/content.json [--human]
```

**Content JSON format:**
```json
{
  "slides": [
    {"layout": "TITLE",        "title": "Presentation Title", "subtitle": "Subtitle"},
    {"layout": "SECTION_HEADER","title": "Section Name",      "subtitle": "Optional"},
    {"layout": "TITLE_AND_BODY","title": "Slide Title",       "body": ["Bullet 1", "Bullet 2"]},
    {"layout": "TITLE_ONLY",   "title": "Title only slide"},
    {"layoutId": "<custom-id>", "title": "Using a branded layout by object ID"}
  ]
}
```

**Supported predefined layouts:**

| Layout | Placeholders | Best for |
|--------|-------------|----------|
| `TITLE` | title + subtitle | Cover slide |
| `SECTION_HEADER` | title + subtitle | Section dividers |
| `TITLE_AND_BODY` | title + body (bullets) | Content slides |
| `TITLE_ONLY` | title | Visual slides |
| `BLANK` | none | Custom layouts |

Use `layoutId` (object ID from the presentation's layouts) instead of `layout` when working with branded templates that have custom masters.

---

### `add_diagrams.py`

Add visual diagrams to specific slides in an existing presentation. Targets slides by their title.

**Usage:**
```bash
python3 /output/gws-slides-analyzer/scripts/add_diagrams.py \
  --presentation-id <id> \
  --target "Slide Title=<diagram-type>" \
  [--target "Another Slide=<diagram-type>" ...]
```

**Diagram types:**

| Type | Description |
|------|-------------|
| `layer` | Stacked horizontal bars — for architecture/layer diagrams |
| `table` | 3-column comparison table with styled header row |
| `two-column` | Side-by-side comparison boxes with shared footer bar |
| `three-box` | Three product/concept boxes with role tags and arrows |

**Examples:**
```bash
python3 /output/gws-slides-analyzer/scripts/add_diagrams.py \
  --presentation-id <id> \
  --target "Architecture Overview=layer" \
  --target "Product Comparison=table" \
  --target "A vs B=two-column" \
  --target "How It Works=three-box"
```

**Notes:**
- Old diagram shapes on the targeted slides are removed and recreated
- Body placeholder text on targeted slides is cleared to make room
- Slide canvas dimensions are hardcoded constants (13.33" × 7.5" standard widescreen)
- The `table`, `two-column`, and `three-box` diagram types contain Red Hat product content (OpenShift AI, RHEL AI, RHAIIS) and are not generic

---

## Common Workflows

### Find and Read a Presentation

```bash
# Step 1: Search
/output/gws-slides-analyzer/scripts/search_slides.sh "quarterly review"

# Step 2: Read using the ID from results
/output/gws-slides-analyzer/scripts/read_slide.sh <presentation-id> --human
```

### Create a Presentation from Scratch

```bash
cat > /tmp/my_slides.json <<'EOF'
{
  "slides": [
    {"layout": "TITLE",         "title": "My Presentation", "subtitle": "Subtitle"},
    {"layout": "SECTION_HEADER","title": "Section 1"},
    {"layout": "TITLE_AND_BODY","title": "Key Points", "body": ["Point 1", "Point 2"]}
  ]
}
EOF

/output/gws-slides-analyzer/scripts/create_presentation.sh \
  --title "My Presentation" \
  --content /tmp/my_slides.json \
  --human
```

### Overwrite an Existing Presentation

```bash
/output/gws-slides-analyzer/scripts/create_presentation.sh \
  --presentation-id <id> \
  --content /tmp/my_slides.json \
  --human
```

### Add Diagrams to Specific Slides

```bash
python3 /output/gws-slides-analyzer/scripts/add_diagrams.py \
  --presentation-id <id> \
  --target "Architecture=layer" \
  --target "Comparison=table"
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Not authenticated | `gws` exits with auth error; run `gws auth login` |
| Presentation not found | `gws` exits with 404 error |
| No permission | `gws` exits with 403 error |
| No search results | Returns `{"total": 0, "files": []}` |
| Invalid predefined layout | Google Slides API rejects the createSlide request |
| Slide title not found | Script reports `NOT FOUND` and skips that target |
