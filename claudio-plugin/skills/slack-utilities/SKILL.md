---
name: slack-utilities
description: Generic Slack utilities for fetching messages, thread replies, posting messages, and converting timestamps using Slack Web API.
compatibility: Requires SLACK_MCP_XOXC_TOKEN and SLACK_MCP_XOXD_TOKEN environment variables
allowed-tools: Bash
---

# Slack Utilities

Generic Slack helper utilities for common Slack operations.

## Overview

This skill provides deterministic scripts for Slack operations:
- **Fetch channel messages** - Retrieve message history with time windows
- **Fetch thread replies** - Retrieve all replies in a thread
- **Post messages** - Send messages to Slack channels
- **Convert timestamps** - Convert Slack timestamps to ISO 8601 format

## Prerequisites

**Required:**
- Environment variables:
  - `SLACK_MCP_XOXC_TOKEN` - Slack cookie token
  - `SLACK_MCP_XOXD_TOKEN` - Slack workspace token
  - `SLACK_WORKSPACE` - Slack workspace name (default: "redhat")
- Python 3.x with `requests` library (`pip3 install -r requirements.txt`)

## Scripts

### Fetch Messages

**Script:** `scripts/slack/fetch_messages.py`

**Purpose:** Fetch Slack channel message history using Slack Web API (`conversations.history`)

**Usage:**
```bash
./scripts/slack/fetch_messages.py <channel_id> <time_window> <output_path> [--filter-date YYYY-MM-DD]
```

**Parameters:**
- `channel_id` - Slack channel ID (e.g., "C08LVA9E1SS")
- `time_window` - Time window (e.g., "65m", "90d", "1w")
- `output_path` - Path to write JSON output
- `--filter-date` - Optional: filter to messages from this date only (YYYY-MM-DD)

**Time Window Format:**
- `m` - minutes (e.g., "65m" = last 65 minutes)
- `h` - hours (e.g., "2h" = last 2 hours)
- `d` - days (e.g., "90d" = last 90 days)
- `w` - weeks (e.g., "1w" = last week)

**Example:**
```bash
./scripts/slack/fetch_messages.py "C08LVA9E1SS" "1h" "/tmp/messages.json"
./scripts/slack/fetch_messages.py "C08LVA9E1SS" "90d" "/tmp/messages.json" --filter-date "2025-12-15"
```

**Output Format:**
- Without `--filter-date`: JSON summary to stdout (`{"message_count": N, "output_path": "..."}`)
- With `--filter-date`: Filtered messages JSON array to stdout, saved to output file

**Exit codes:**
- 0 = success
- 1 = invalid params
- 2 = API error
- 4 = auth error

---

### Fetch Thread Replies

**Script:** `scripts/slack/fetch_thread_replies.py`

**Purpose:** Fetch thread replies using Slack Web API (`conversations.replies`)

**Usage:**
```bash
./scripts/slack/fetch_thread_replies.py <channel_id> <thread_ts> <output_path>
```

**Parameters:**
- `channel_id` - Slack channel ID
- `thread_ts` - Thread timestamp (e.g., "1769005300.000000")
- `output_path` - Path to write JSON output

**Example:**
```bash
./scripts/slack/fetch_thread_replies.py "C08LVA9E1SS" "1769005300.000000" "/tmp/thread.json"
```

**Output Format:**
JSON array of thread messages including the parent message and all replies:
```json
[
  {
    "ts": "1769005300.000000",
    "user": "U12345678",
    "text": "Parent message...",
    "thread_ts": "1769005300.000000"
  },
  {
    "ts": "1769005400.000000",
    "user": "U87654321",
    "text": "Reply message...",
    "thread_ts": "1769005300.000000"
  }
]
```

**Exit codes:**
- 0 = success
- 1 = invalid params
- 2 = API error
- 4 = auth error

---

### Post Message

**Script:** `scripts/slack/post_message.py`

**Purpose:** Post messages to Slack channels using Slack Web API (`chat.postMessage`)

**Usage:**
```bash
./scripts/slack/post_message.py <channel_id> <message_text>
```

**Parameters:**
- `channel_id` - Slack channel ID
- `message_text` - Message to post (supports markdown)

**Example:**
```bash
./scripts/slack/post_message.py "C09G0CMTUNA" "Release completed successfully!"
```

**Markdown Support:**
The message text supports Slack markdown formatting:
- `*bold*` - Bold text
- `_italic_` - Italic text
- `~strikethrough~` - Strikethrough text
- `` `code` `` - Inline code
- ` ```code block``` ` - Code block
- `<url|text>` - Hyperlinks

**Output Format:**
JSON response from Slack API:
```json
{
  "ok": true,
  "channel": "C09G0CMTUNA",
  "ts": "1704897000.123456",
  "message": {
    "text": "Release completed successfully!",
    "user": "U12345678",
    "type": "message",
    "ts": "1704897000.123456"
  }
}
```

**Exit codes:**
- 0 = success
- 1 = invalid params
- 2 = API error
- 4 = auth error

---

### Convert Timestamp

**Script:** `scripts/parsing/convert_timestamp.py`

**Purpose:** Convert Slack timestamps to ISO 8601 format

**Usage:**
```bash
./scripts/parsing/convert_timestamp.py <slack_timestamp>
```

**Parameters:**
- `slack_timestamp` - Slack timestamp (e.g., "1704897000.123456")

**Output:** ISO 8601 timestamp with UTC timezone (e.g., "2025-01-10T15:30:00Z")

**Example:**
```bash
ISO_TIME=$(./scripts/parsing/convert_timestamp.py "1704897000.123456")
echo "$ISO_TIME"  # 2025-01-10T15:30:00Z
```

**Slack Timestamp Format:**
Slack timestamps are Unix timestamps (seconds since epoch) with microseconds:
- Format: `SSSSSSSSSS.MMMMMM`
- Example: `1704897000.123456`
  - `1704897000` = Unix timestamp (seconds)
  - `.123456` = Microseconds (not used in conversion)

**Exit codes:**
- 0 = success
- 1 = invalid params
- 3 = parsing error

---

## Usage Notes

**Authentication:**
- All scripts that interact with Slack require `SLACK_MCP_XOXC_TOKEN` and `SLACK_MCP_XOXD_TOKEN`
- Tokens can be provided via environment variables or command-line arguments
- Default workspace is "redhat" (can be overridden with `SLACK_WORKSPACE`)

**Error Handling:**
- All scripts use consistent exit codes (see each script's documentation)
- Errors are written to stderr
- Success output written to stdout (JSON or plain text)

**Output Formats:**
- fetch_messages and fetch_thread_replies: JSON array of messages
- post_message: JSON response from Slack API
- convert_timestamp: ISO 8601 timestamp string

## Integration with Other Skills

These utilities are designed to be imported and used by product-specific skills:

```python
# In a product-specific skill
import sys
sys.path.append('/path/to/slack-utilities/scripts')
from slack.fetch_messages import fetch_messages
from parsing.convert_timestamp import convert_timestamp
```

Or called as standalone scripts:

```bash
# Fetch recent messages
/path/to/slack-utilities/scripts/slack/fetch_messages.py "C08LVA9E1SS" "1h" "/tmp/out.json"
```

## Common Workflows

### Example 1: Fetch and Parse Recent Messages

```bash
# Fetch messages from last hour
./scripts/slack/fetch_messages.py "C08LVA9E1SS" "1h" "/tmp/messages.json"

# Parse the output
cat /tmp/messages.json | jq '.[].text'
```

### Example 2: Fetch Thread Conversation

```bash
# First, find a message with replies
MESSAGES=$(./scripts/slack/fetch_messages.py "C08LVA9E1SS" "1d" "/tmp/messages.json")
THREAD_TS=$(echo "$MESSAGES" | jq -r '.[0].thread_ts')

# Fetch the full thread
./scripts/slack/fetch_thread_replies.py "C08LVA9E1SS" "$THREAD_TS" "/tmp/thread.json"
```

### Example 3: Post Status Update

```bash
# Post a simple message
./scripts/slack/post_message.py "C09G0CMTUNA" "Build completed successfully"

# Post a formatted message
./scripts/slack/post_message.py "C09G0CMTUNA" "*Build Status:* Success\n\`\`\`Version: 3.2.3-2025101401\`\`\`"
```

### Example 4: Convert Timestamps for Display

```bash
# Fetch messages
./scripts/slack/fetch_messages.py "C08LVA9E1SS" "1h" "/tmp/messages.json"

# Convert timestamps to human-readable format
cat /tmp/messages.json | jq -r '.[].ts' | while read ts; do
    echo "Message at: $(./scripts/parsing/convert_timestamp.py $ts)"
done
```

## Troubleshooting

**Authentication errors (exit code 4):**
- Check that `SLACK_MCP_XOXC_TOKEN` and `SLACK_MCP_XOXD_TOKEN` are set
- Verify tokens are valid and not expired
- Ensure workspace name matches your Slack workspace

**API errors (exit code 2):**
- Check network connectivity
- Verify channel IDs are correct (should start with 'C')
- Check Slack API status at https://status.slack.com
- For post_message: Ensure bot has permission to post to the channel

**Parsing errors (exit code 3):**
- Verify timestamp format is correct (Unix timestamp with microseconds)
- Check that message JSON is valid

**No messages returned:**
- Verify the channel ID is correct
- Check the time window is appropriate (may be too short)
- Ensure the bot has access to the channel
- For private channels, the bot must be invited

## Dependencies

**Python packages:**
- `requests>=2.31.0` - For Slack API calls

**Install Python dependencies:**
```bash
pip3 install -r requirements.txt
```

## Testing

Run the test suite:
```bash
cd tests/
pip3 install -r ../requirements-test.txt
pytest -v
```

**Test timestamp conversion (no auth needed):**
```bash
./scripts/parsing/convert_timestamp.py "1704897000.123456"
# Expected: 2024-01-10T14:30:00Z
```

## Security Considerations

**Token Management:**
- Never commit Slack tokens to version control
- Use environment variables or secret management systems
- Rotate tokens regularly
- Limit token permissions to only what's needed

**Channel Access:**
- Ensure the bot only has access to authorized channels
- Review channel permissions before posting
- Be cautious when posting to public channels

**Data Handling:**
- Slack message data may contain sensitive information
- Don't log or store tokens in plaintext
- Clean up temporary files after use

## Version History

**v2.0.0 (2025-02-18)**
- Replaced slackdump wrappers with direct Slack Web API calls
- Added `--filter-date` flag on `fetch_messages.py`
- Added `filter_messages_by_date()` function
- Added test infrastructure (pytest)
- Removed slackdump dependency

**v1.0.0 (2025-02-12)**
- Initial release
- Extracted from aipcc-claudio downstream project
- Scripts: fetch_messages, fetch_thread_replies, post_message, convert_timestamp
- Generic utilities for any Slack-based workflow
