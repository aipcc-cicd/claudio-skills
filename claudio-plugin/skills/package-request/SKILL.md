---
name: package-request
description: Submit a package onboarding request — creates a Jira epic and triggers the onboarding pipeline. Use when the user asks to request a package, onboard a package, or submit a package request.
compatibility: Requires jq, curl, and glab. Requires JIRA_SITE, JIRA_TOKEN, JIRA_EMAIL, and GITLAB_TOKEN environment variables.
allowed-tools: Bash(*/package-request/scripts/submit.sh *),Bash(*/package-request/scripts/list_teams.sh *),Bash(*/tools/*/install.sh *)
---

# Package Request

Submit package onboarding requests. Creates a Jira epic and triggers the package-onboarding GitLab pipeline.

## Prerequisites

- `jq` — JSON processor (install via `../../../tools/jq/install.sh`)
- `curl` — HTTP client (typically pre-installed)
- `glab` — GitLab CLI (install via `../../../tools/glab/install.sh`)

## Configuration

| Variable | Default | Description |
|---|---|---|
| `JIRA_SITE` | (required) | Atlassian site hostname (e.g. `redhat.atlassian.net`) |
| `JIRA_TOKEN` | (required) | Atlassian API token |
| `JIRA_EMAIL` | (required) | Atlassian account email |
| `GITLAB_TOKEN` | (required) | GitLab personal access token for pipeline trigger |
| `JIRA_PROJECT` | `AIPCC` | Jira project key for epic creation |
| `JIRA_COMPONENT` | `Accelerator Enablement` | Component set on created epics |

## Interaction Flow

Follow these steps precisely:

### Step 1: Parse user input

Extract any fields the user provided upfront. The user may provide anywhere from zero to all fields. Map what they gave to the fields below.

**Required fields** (must collect all before submitting):

| Field | Arg name | Type | Constraints |
|---|---|---|---|
| Package name | `--package-name` | string | 1-255 chars, no version specifiers (`=<>!~`). Extras syntax is ok (e.g. `torch[cuda]`) |
| Requester | `--requester` | string | Email, kerberos ID, or display name. Must exist in Jira |
| Jira project | *(not sent to script)* | string | `RHAISTRAT` or `AIPCC` — used to fetch team options in Step 2 |
| Team | `--team` | string | Must be a component from the selected Jira project |
| Related Jira ticket | `--jira-id` | string | Format: `PROJECT-NUMBER` (e.g. `RHELAI-123`) |
| Business justification | `--justification` | string | 10-5000 chars |
| Delivery timeline | `--delivery-timeline` | date | ISO format (YYYY-MM-DD), must be at least 8 days from today |

**Conditionally required:**
- Source URL (`--source-url`) — required when package source is `git` or `other`

### Step 2: Collect missing required fields

For each missing required field, ask the user one question at a time.

**For the Team field:** fetch available teams first:
```bash
${CLAUDE_SKILL_DIR}/scripts/list_teams.sh JIRA_PROJECT
```
Replace `JIRA_PROJECT` with the user's selected Jira project (`RHAISTRAT` or `AIPCC`). The script outputs a JSON array of component names. Present them as options for the user to choose from.

**For Delivery timeline:** validate that the date is at least 8 days from today before proceeding.

**For Jira ID:** validate the format matches `PROJECT-NUMBER` (uppercase letters, dash, digits).

### Step 3: Offer optional fields

Once all required fields are collected, tell the user about these optional fields and ask if they want to fill any or proceed:

| Field | Arg name | Notes |
|---|---|---|
| Extras | `--extras` | Comma-separated PEP 508 identifiers (e.g. `cuda,tensor`). Also parsed automatically from package name if brackets are present |
| Package source | `--package-source` | `pypi` (default), `git`, or `other` |
| Source URL | `--source-url` | Required for git/other sources |
| Version | `--version` | PEP 440 version or specifier (e.g. `2.0.0`, `>=1.5.0`, `~=1.4`) |
| Backport versions | `--backport-versions` | Comma-separated stable series (e.g. `3.4,3.5-EA1`) |
| Release targets | `--release-target` | Comma-separated target product versions (e.g. `RHAI 3.6,RHAIIS 3.4`) |
| Release commitment | `--release-commitment` | Max 2000 chars |
| Hardware requirements | `--other-hardware` | Max 500 chars |
| Testing requirements | `--testing-requirements` | Max 2000 chars |

Backport versions and release targets are free-text — the user types them directly (e.g. `3.4, 3.5-EA1`).

### Step 4: Confirm and submit

Show a summary table of all fields being submitted. Ask for explicit confirmation before proceeding.

Once confirmed, call the submit script:

```bash
${CLAUDE_SKILL_DIR}/scripts/submit.sh \
    --package-name "NAME" \
    --requester "EMAIL" \
    --team "TEAM" \
    --jira-id "ID" \
    --justification "TEXT" \
    --delivery-timeline "YYYY-MM-DD" \
    [--extras "a,b,c"] \
    [--package-source "pypi|git|other"] \
    [--source-url "URL"] \
    [--version "VER"] \
    [--backport-versions "3.4,3.5-EA1"] \
    [--release-target "RHAI 3.6,RHAIIS 3.4"] \
    [--release-commitment "TEXT"] \
    [--other-hardware "TEXT"] \
    [--testing-requirements "TEXT"]
```

The script outputs a result type on the first line and JSON on the remaining lines. Parse both.

### Step 5: Handle the response

**`SUCCESS`:**
Parse the JSON and show:
- Jira ticket: `ticket_url` (clickable link)
- Pipeline: `pipeline_url` (if present, clickable link)
- Package: `package_name`

Example:
```json
{"ticket_id":"AIPCC-1234","ticket_url":"https://redhat.atlassian.net/browse/AIPCC-1234","package_name":"torch[cuda]","message":"Package request created successfully","pipeline_url":"https://gitlab.com/..."}
```

**`PRODUCTION_WARNING`:**
The package already exists in production repositories. Show the warning details:
- `details.found_in[].product_version` and `details.found_in[].variant` for each repo
- `details.found_in[].repo_url` as clickable links

Ask the user: "This package already exists in these production repos. Do you still want to submit the request?"

If yes, re-run the submit script with `--skip-production-check` added.

Example:
```json
{"warning":"production_exists","message":"Note: this check does not verify whether the requested extras are available.","details":{"package_name":"torch","found_in":[{"product_version":"3.4","variant":"cpu-ubi9","repo_url":"https://..."}]}}
```

**`DUPLICATE`:**
Show the existing tickets from `existing_tickets[]`:
- `ticket_id` and `ticket_url` for each
- `summary` for context

Tell the user a similar request was submitted in the past 3 days and show the existing tickets.

Example:
```json
{"message":"A request overlapping with '...' was submitted in the past 3 days.","existing_tickets":[{"ticket_id":"AIPCC-1234","ticket_url":"...","summary":"..."}],"total":1}
```

**`VALIDATION_ERROR`:**
Parse `message` and tell the user which validation failed and why. Ask them to correct the relevant field, then re-run the submit script with the corrected value.

Example:
```json
{"message":"Package 'nonexistent' not found on PyPI. Verify at https://pypi.org/search/?q=nonexistent"}
```

**Exit code 1 (from script):**
Invalid parameters. This shouldn't happen if the skill collected all required fields correctly.

**Exit code 2 (from script):**
A network error occurred (Jira API or curl failure). Suggest retrying.

**Exit code 3 (from script):**
Missing Jira authentication environment variables. Tell the user to configure `JIRA_SITE`, `JIRA_TOKEN`, and `JIRA_EMAIL`.

### Step 6: Offer to submit another request

After handling the response (success or failure), ask the user if they want to submit another package request. If yes, go back to Step 1. If no, end the conversation.

## Exit Codes (submit.sh)

| Code | Meaning |
|------|---------|
| 0 | Result produced (check result type on first line of output) |
| 1 | Invalid parameters (missing required arguments) |
| 2 | Network/API error (Jira, curl, or GitLab failure) |
| 3 | Missing authentication (JIRA_SITE, JIRA_TOKEN, or JIRA_EMAIL not set) |
