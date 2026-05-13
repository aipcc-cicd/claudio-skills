---
name: gws-doc-action-extractor
description: Scan Google Docs shared with you for action patterns (e.g. "create a card", "action item", "open a ticket") in both content and comments, extract them as structured data, and create Jira issues. Use when the user asks to scan docs for actions, find TODOs in Google Docs, or automatically create Jira cards from document content.
allowed-tools: Bash(gws drive files list:*),Bash(gws drive files get:*),Bash(gws drive files export:*),Bash(gws auth:*),Bash(/output/gws-doc-action-extractor/scripts/*.sh:*),Bash(*/jira-utilities/scripts/*.sh:*)
---

# Google Docs Action Extractor

## Overview

Scan Google Docs for action patterns in content and inline comments, then create Jira cards from the extracted items.

**Prerequisites:**
- `gws` available and authenticated
- `jq` for JSON parsing
- Jira credentials set: `JIRA_SITE`, `JIRA_TOKEN`, `JIRA_EMAIL`

## Detected Patterns

| Pattern type | Examples |
|---|---|
| **Explicit card request** | "create a card", "create a ticket", "open a jira", "file a bug" |
| **Action items section** | Lines listed under "Action items:" in meeting docs |
| **Assignee actions** | "[Name] to do X", "[Name] will X" |
| **TODO markers** | "TODO:", "ACTION:", "FOLLOW UP:", "FOLLOWUP:" |
| **Google Doc comments** | Inline comment text `[a]...[z]` appended at end of export |

## Available Scripts

### `scan_docs.sh`

Search all shared docs for action patterns using Drive full-text search.

**Usage:**
```bash
/output/gws-doc-action-extractor/scripts/scan_docs.sh [OPTIONS]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--limit N` | `20` | Max docs to return per pattern |
| `--human` | — | Human-readable output |

**Output:** JSON list of matching docs with hit count per pattern type.

---

### `extract_actions.sh`

Extract all action items from a specific Google Doc.

**Usage:**
```bash
/output/gws-doc-action-extractor/scripts/extract_actions.sh <file-id> [OPTIONS]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--human` | — | Human-readable output |

**Output JSON:**
```json
{
  "doc_id": "...",
  "doc_name": "...",
  "doc_link": "...",
  "actions": [
    {
      "type": "action_item",
      "text": "Alice to coordinate with Bob on the release plan",
      "assignee": "Alice",
      "line": 42,
      "context": "surrounding line"
    },
    {
      "type": "create_card",
      "text": "create a card for tracking the dependency delay",
      "assignee": "",
      "line": 110,
      "context": "surrounding line"
    }
  ]
}
```

---

### `extract_recent_actions.sh`

Extract action items only from content added in the last N days. Identifies date-labeled sections (e.g. `Apr 27, 2026`), restricts parsing to those sections, and builds a full Jira description including surrounding context for each action.

**Usage:**
```bash
/output/gws-doc-action-extractor/scripts/extract_recent_actions.sh <file-id> [OPTIONS]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--days N` | `7` | Look back N days |
| `--human` | — | Human-readable output |

**Examples:**
```bash
# Last 7 days, human-readable
/output/gws-doc-action-extractor/scripts/extract_recent_actions.sh <file-id> --human

# Last 14 days, pipe to Jira card creator
/output/gws-doc-action-extractor/scripts/extract_recent_actions.sh <file-id> --days 14 \
  | /output/gws-doc-action-extractor/scripts/create_jira_cards.sh --project <PROJECT-KEY> --dry-run
```

**Output JSON per action includes:**
- `section_date` — the date header of the section it came from
- `type` — `create_card`, `assignee_action`, `ai_action`, `spike`
- `text` — the matched line
- `assignee` — extracted name if present
- `context` — ±3 lines surrounding the match
- `jira_description` — ready-to-use Jira card body with source, date, context and full section

---

### `create_jira_cards.sh`

Create Jira issues from extracted actions (reads output of `extract_actions.sh`).

**Usage:**
```bash
/output/gws-doc-action-extractor/scripts/extract_actions.sh <file-id> \
  | /output/gws-doc-action-extractor/scripts/create_jira_cards.sh [OPTIONS]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--project KEY` | required | Jira project key (e.g. `<PROJECT-KEY>`) |
| `--type TYPE` | `Task` | Issue type (Task, Bug, Story) |
| `--dry-run` | — | Print what would be created, don't call Jira |

---

## Typical Workflow

### Check recent changes and suggest cards (most common)

```bash
# Review last 7 days across a doc and suggest cards
/output/gws-doc-action-extractor/scripts/extract_recent_actions.sh <file-id> --days 7 --human

# Pipe directly to Jira card creator (dry-run first)
/output/gws-doc-action-extractor/scripts/extract_recent_actions.sh <file-id> --days 7 \
  | /output/gws-doc-action-extractor/scripts/create_jira_cards.sh --project <PROJECT-KEY> --dry-run
```



### Scan all shared docs then create cards

```bash
# Step 1: Find docs with action patterns
/output/gws-doc-action-extractor/scripts/scan_docs.sh --human

# Step 2: Extract actions from a specific doc
/output/gws-doc-action-extractor/scripts/extract_actions.sh <file-id> --human

# Step 3: Review and create Jira cards (dry-run first)
/output/gws-doc-action-extractor/scripts/extract_actions.sh <file-id> \
  | /output/gws-doc-action-extractor/scripts/create_jira_cards.sh --project <PROJECT-KEY> --dry-run

# Step 4: Create for real
/output/gws-doc-action-extractor/scripts/extract_actions.sh <file-id> \
  | /output/gws-doc-action-extractor/scripts/create_jira_cards.sh --project <PROJECT-KEY>
```

### Agent workflow (Claude handles review + creation)

1. Run `scan_docs.sh` to find candidate docs
2. Run `extract_actions.sh` on each doc
3. Present extracted actions to user for confirmation
4. Run `create_jira_cards.sh` for confirmed actions only

## Error Handling

| Scenario | Behavior |
|----------|----------|
| No actions found | Returns `{"actions": []}` |
| Jira auth missing | `create_jira_cards.sh` exits with clear error |
| Doc not accessible | `extract_actions.sh` exits with 403/404 |
