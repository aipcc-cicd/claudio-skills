---
name: gws-calendar-reader
description: Check Google Calendar for team availability and upcoming events. Use when the user asks about free/busy status, team schedules, upcoming events, or calendar availability. Uses the Google Workspace CLI (gws). Requires prior authentication via `gws auth login` or a service account credential file.
allowed-tools: Bash(gws calendar freebusy:*),Bash(gws calendar events:*),Bash(gws auth:*),Bash(/output/gws-calendar-reader/scripts/*.sh:*)
---

# Google Calendar Reader

## Overview

Check team availability and upcoming calendar events using the [Google Workspace CLI](https://github.com/googleworkspace/cli) (`gws`).

**Prerequisites:**
- `gws` command is available and in PATH
- User is already authenticated (`gws auth login` or service account)
- `jq` for JSON parsing
- Team members have shared their calendar with the authenticated user (for agenda; free/busy works with any sharing level)

## Authentication

| Method | How to set up |
|--------|--------------|
| Interactive OAuth | `gws auth login` — browser-based consent flow |
| Service Account | Set `GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/path/to/sa.json` |
| Pre-obtained token | Set `GOOGLE_WORKSPACE_CLI_TOKEN=<token>` |

## Configuration

Team members and the default timezone are configured in `/output/gws-calendar-reader/team.json`:

```json
{
  "timezone": "Europe/Prague",
  "calendars": [
    {
      "name": "Team Calendar",
      "id": "<calendar-id>@group.calendar.google.com",
      "type": "group"
    }
  ],
  "team": [
    {"name": "Member Name", "email": "member@example.com"}
  ]
}
```

> **Note:** If team member emails are not yet in `team.json`, use `--emails` to pass them directly.

## Available Scripts

### `check_freebusy.sh`

Check whether team members are free or busy over a given time window.

**Usage:**
```bash
/output/gws-calendar-reader/scripts/check_freebusy.sh [OPTIONS]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--emails EMAIL,...` | from `team.json` | Comma-separated email addresses (overrides team.json) |
| `--hours N` | `8` | Check the next N hours from now |
| `--today` | — | Check the rest of today |
| `--date YYYY-MM-DD` | — | Check a full specific day |
| `--timezone TZ` | from `team.json` | IANA timezone (e.g. `Europe/Prague`) |
| `--human` | — | Human-readable output instead of JSON |

**Examples:**
```bash
# Check next 8 hours for all team members
/output/gws-calendar-reader/scripts/check_freebusy.sh --human

# Check free/busy for specific people today
/output/gws-calendar-reader/scripts/check_freebusy.sh --emails alice@example.com,bob@example.com --today --human

# Check a specific date
/output/gws-calendar-reader/scripts/check_freebusy.sh --date 2026-05-10 --human
```

---

### `team_agenda.sh`

Show upcoming calendar events for team members.

**Usage:**
```bash
/output/gws-calendar-reader/scripts/team_agenda.sh [OPTIONS]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--email EMAIL` | all in `team.json` | Show agenda for one person (`me` = your own calendar) |
| `--days N` | `1` | Number of days ahead to show |
| `--timezone TZ` | from `team.json` | IANA timezone override |
| `--human` | — | Human-readable output instead of JSON |

**Examples:**
```bash
# Show today's agenda for all team members
/output/gws-calendar-reader/scripts/team_agenda.sh --human

# Show your own agenda for the next 5 days
/output/gws-calendar-reader/scripts/team_agenda.sh --email me --days 5 --human

# Show one person's agenda for tomorrow
/output/gws-calendar-reader/scripts/team_agenda.sh --email alice@example.com --days 2 --human
```

---

## Common Workflows

### Check if the team is free for a meeting now

```bash
/output/gws-calendar-reader/scripts/check_freebusy.sh --hours 2 --human
```

### See what's on the team's agenda this week

```bash
/output/gws-calendar-reader/scripts/team_agenda.sh --days 7 --human
```

### Check availability for a specific date

```bash
# Step 1: Free/busy overview
/output/gws-calendar-reader/scripts/check_freebusy.sh --date 2026-05-10 --human

# Step 2: Detailed agenda for that day (requires calendar sharing)
/output/gws-calendar-reader/scripts/team_agenda.sh --days 1 --human
```

## Calendar Access Levels

| Sharing level | `check_freebusy.sh` | `team_agenda.sh` |
|---------------|---------------------|------------------|
| Free/busy only | Works (shows busy blocks, no titles) | Shows "(no title)" for events |
| See all event details | Works | Shows full event titles and details |

> If a calendar is shared at free/busy level only, event titles will not be visible. The calendar owner must upgrade sharing to "See all event details" for full access.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Not authenticated | `gws` exits with auth error; run `gws auth login` |
| Calendar not shared | `team_agenda.sh` skips that member with a warning |
| No team members in `team.json` | Use `--emails` or `--email` to pass addresses directly |
| `team.json` missing | Error with instructions to create it or use `--emails` |
