---
name: slack-webhook
description: Post messages to Slack via incoming webhook URLs. Supports plain text and Slack Block Kit JSON.
compatibility: Requires SLACK_WEBHOOK_URL environment variable.
allowed-tools: Bash(*/slack-webhook/scripts/post-to-slack.sh *),Bash(*/tools/*/install.sh *)
---

# Slack Webhook

Post messages to Slack channels via incoming webhook URLs. This is a notification-only skill — no reading or searching. For full Slack API access (fetch messages, search channels, threads), use the `slack-utilities` skill instead.

## Prerequisites

**Required:**
- `SLACK_WEBHOOK_URL` - Slack incoming webhook URL (create one at https://api.slack.com/messaging/webhooks)
- `curl` - HTTP client (typically pre-installed)
- `jq` - JSON processor (install via `tools/jq/install.sh`)

## Script: post-to-slack.sh

**Usage:**
```bash
${CLAUDE_SKILL_DIR}/scripts/post-to-slack.sh [--check] [--blocks] "<message_or_json>"
```

**Flags:**
- `--check` - Verify `SLACK_WEBHOOK_URL` is set without sending a message
- `--blocks` - Treat the argument as a Slack Block Kit JSON array instead of plain text

**Environment Variables:**
- `SLACK_WEBHOOK_URL` (required) - The incoming webhook URL

## Examples

### Plain text message

```bash
${CLAUDE_SKILL_DIR}/scripts/post-to-slack.sh "Build completed successfully"
```

### Formatted text (Slack mrkdwn)

```bash
${CLAUDE_SKILL_DIR}/scripts/post-to-slack.sh "*Build Status:* :white_check_mark: Success\nVersion: \`3.2.3\`"
```

### Block Kit JSON

```bash
${CLAUDE_SKILL_DIR}/scripts/post-to-slack.sh --blocks '[
  {
    "type": "header",
    "text": {"type": "plain_text", "text": "Release v3.2.3"}
  },
  {
    "type": "section",
    "text": {"type": "mrkdwn", "text": "*Status:* Deployed to production\n*Duration:* 12m 34s"}
  }
]'
```

### Preflight check

```bash
${CLAUDE_SKILL_DIR}/scripts/post-to-slack.sh --check
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid parameters (missing message, missing env var, invalid JSON) |
| 2 | Webhook error (network failure or non-200 HTTP response) |

## Differences from slack-utilities

| | slack-webhook | slack-utilities |
|---|---|---|
| Auth | `SLACK_WEBHOOK_URL` | `SLACK_XOXC_TOKEN` + `SLACK_XOXD_TOKEN` |
| Capabilities | Post only | Read, search, post, threads |
| Language | Bash (curl + jq) | Python (requests) |
| Dependencies | curl + jq | pip install requests |
| Use case | Simple notifications | Full Slack integration |

## Troubleshooting

**"SLACK_WEBHOOK_URL not set"** - Export the webhook URL: `export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../..."`

**HTTP 403/404** - The webhook URL may be invalid or revoked. Create a new one in your Slack workspace settings.

**HTTP 400 with --blocks** - The Block Kit JSON is malformed. Validate it at https://app.slack.com/block-kit-builder.

**"invalid Block Kit JSON"** - The argument passed with `--blocks` is not valid JSON. Ensure it's a JSON array of block objects.
