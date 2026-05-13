---
name: gws-drive-reader
description: Read and search Google Drive files (Docs, Sheets, Slides, and plain files). Use when the user asks to list, search, or read the content of any file in Google Drive, including Google Docs and Google Sheets. Uses the Google Workspace CLI (gws). Requires prior authentication via `gws auth login` or a service account credential file.
allowed-tools: Bash(gws drive files list:*),Bash(gws drive files get:*),Bash(gws drive files export:*),Bash(gws auth:*),Bash(*/gws-drive-reader/scripts/*.sh:*),Bash(*/tools/*/install.sh:*)
---

# Google Drive Reader

## Overview

Read, search, and list files from Google Drive using the [Google Workspace CLI](https://github.com/googleworkspace/cli) (`gws`).

**Prerequisites:**
- `gws` command is available (install via `tools/google-workspace-cli/install.sh`)
- User is already authenticated (`gws auth login` or service account)
- `jq` for JSON parsing (optional but recommended)

**Dependency Installation:**
Before running any script, install required tools:

```bash
../../../tools/google-workspace-cli/install.sh  # Install gws if not present
../../../tools/jq/install.sh                    # Install jq if not present
```

## Authentication

The `gws` CLI supports several authentication modes:

| Method | How to set up |
|--------|--------------|
| Interactive OAuth | `gws auth login` - browser-based consent flow |
| Service Account | Set `GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/path/to/sa.json` |
| Pre-obtained token | Set `GOOGLE_WORKSPACE_CLI_TOKEN=<token>` |

For non-interactive environments (CI/CD, automated agents), service account authentication is recommended.

## Core Concepts

- **File ID**: The unique identifier for any Google Drive file/folder (found in the URL: `drive.google.com/file/d/<FILE_ID>/`)
- **Google-native types**: Docs, Sheets, Slides require export to convert to readable text
- **Search syntax**: Supports Google Drive query syntax (`name contains`, `fullText contains`, `mimeType =`, etc.)

## Available Scripts

### `list_files.sh`

List files in Google Drive with optional filtering.

**Usage:**
```bash
./scripts/list_files.sh [OPTIONS]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--folder-id ID` | (root) | List files within a specific folder |
| `--shared-with-me` | -- | List only files shared with you (not owned by you) |
| `--since N` | -- | Only files modified in the last N days |
| `--limit N` | `50` | Maximum number of files to return |
| `--type TYPE` | (all) | Filter by type: `doc`, `sheet`, `slide`, `folder`, or a full MIME type |
| `--human` | -- | Human-readable table output |

**Examples:**
```bash
# List recent files (JSON)
./scripts/list_files.sh

# List all files shared with you
./scripts/list_files.sh --shared-with-me

# List files in a specific folder
./scripts/list_files.sh --folder-id 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs

# List Google Docs only, human-readable
./scripts/list_files.sh --type doc --human

# List up to 100 files
./scripts/list_files.sh --limit 100
```

**Output (JSON):**
```json
{
  "total": 3,
  "files": [
    {
      "id": "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74NxxH4",
      "name": "Q1 Report",
      "type": "document",
      "mimeType": "application/vnd.google-apps.document",
      "modifiedTime": "2026-04-01T10:00:00.000Z",
      "size": "N/A",
      "webViewLink": "https://docs.google.com/document/d/..."
    }
  ]
}
```

---

### `search_files.sh`

Search for files by name or content.

**Usage:**
```bash
./scripts/search_files.sh <query> [OPTIONS]
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `<query>` | Yes | Search term (searches name and full text) |

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--limit N` | `20` | Maximum number of results |
| `--type TYPE` | (all) | Filter by type: `doc`, `sheet`, `slide`, `folder`, or a full MIME type string |
| `--human` | -- | Human-readable output |

**Examples:**
```bash
# Search for files containing "budget"
./scripts/search_files.sh "budget"

# Search for Google Sheets named "quarterly"
./scripts/search_files.sh "quarterly" --type sheet

# Quick name search, human-readable
./scripts/search_files.sh "release notes" --limit 5 --human
```

**Output (JSON):**
```json
{
  "query": "release notes",
  "total": 2,
  "files": [
    {
      "id": "...",
      "name": "Release Notes v1.2",
      "type": "document",
      "mimeType": "application/vnd.google-apps.document",
      "modifiedTime": "2026-03-15T09:30:00.000Z",
      "webViewLink": "https://docs.google.com/document/d/..."
    }
  ]
}
```

---

### `read_document.sh`

Read/export the content of a specific Google Drive file.

**Usage:**
```bash
./scripts/read_document.sh <file-id> [OPTIONS]
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `<file-id>` | Yes | Google Drive file ID |

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--format FORMAT` | `text` | Export format: `text` (plain text), `html` |
| `--human` | -- | Human-readable output (prints content directly) |

**Export format by file type:**

| Source Type | text | html |
|-------------|------|------|
| Google Docs | plain text | HTML |
| Google Sheets | CSV | CSV |
| Google Slides | plain text | plain text |
| Plain text/code | raw content | raw content |

**Examples:**
```bash
# Read a Google Doc as plain text (JSON)
./scripts/read_document.sh 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74NxxH4

# Read and print directly (human mode)
./scripts/read_document.sh 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74NxxH4 --human

# Export as HTML
./scripts/read_document.sh 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74NxxH4 --format html
```

**Output (JSON):**
```json
{
  "id": "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74NxxH4",
  "name": "Q1 Report",
  "mimeType": "application/vnd.google-apps.document",
  "modifiedTime": "2026-04-01T10:00:00.000Z",
  "webViewLink": "https://docs.google.com/document/d/...",
  "exportFormat": "text",
  "content": "Q1 Report\n\nExecutive Summary\n..."
}
```

---

## Common Workflows

### Workflow 1: Find and Read a Document

**User Request:** "Read the Q1 report from Google Drive"

```bash
# Step 1: Search for the document
./scripts/search_files.sh "Q1 report" --type doc

# Step 2: Read the document using the ID from search results
./scripts/read_document.sh <file-id-from-search>
```

### Workflow 2: List All Documents in a Folder

**User Request:** "What documents are in the Engineering folder?"

```bash
# Step 1: Find the folder
./scripts/search_files.sh "Engineering" --type folder

# Step 2: List files in the folder
./scripts/list_files.sh --folder-id <folder-id>
```

### Workflow 3: Read Multiple Documents in Parallel

**User Request:** "Summarize all release notes documents"

```bash
# Step 1: Search and capture all matching file IDs
OUTPUT=$(./scripts/search_files.sh "release notes" --type doc)
FILE_IDS=$(echo "$OUTPUT" | jq -r '.files[].id')

# Step 2: Read each document (in parallel via multiple tool calls)
# ./scripts/read_document.sh <id1>
# ./scripts/read_document.sh <id2>
# ./scripts/read_document.sh <id3>
```

### Workflow 4: Extract Specific Content from a Spreadsheet

**User Request:** "Get the budget data from the Q1 spreadsheet"

```bash
# Step 1: Find the spreadsheet
./scripts/search_files.sh "Q1 budget" --type sheet

# Step 2: Export as CSV
./scripts/read_document.sh <file-id> --format text

# Step 3: Parse the CSV content from the JSON output
OUTPUT=$(./scripts/read_document.sh <file-id>)
echo "$OUTPUT" | jq -r '.content'
```

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Not authenticated | `gws` exits with auth error; run `gws auth login` |
| File not found | `gws` exits with 404 error |
| No export permission | `gws` exits with 403 error |
| Google Folder passed to read_document.sh | Error: folders have no exportable content |
| No files matching search | Returns `{"total": 0, "files": []}` |

## Dependencies

**Required:**
- `gws` - Google Workspace CLI
  - Install: `../../../tools/google-workspace-cli/install.sh`
  - Check: `../../../tools/google-workspace-cli/install.sh --check`

**Optional (recommended):**
- `jq` - JSON processor for parsing outputs
  - Install: `../../../tools/jq/install.sh`
