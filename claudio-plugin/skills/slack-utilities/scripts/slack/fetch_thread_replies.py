#!/usr/bin/env python3
"""Fetch Slack thread replies using Slack Web API.

This script fetches thread replies using direct Slack API calls
with proper error handling.

Exit Codes:
    0: Success
    1: Invalid parameters
    2: API error
    4: Authentication error
"""

import argparse
import json
import os
import sys
import time
from typing import Optional

import requests


def fetch_thread_replies(
    channel_id: str,
    thread_ts: str,
    output_path: str,
    xoxc_token: Optional[str] = None,
    xoxd_token: Optional[str] = None,
    workspace: str = "redhat"
) -> list:
    """Fetch Slack thread replies using Slack Web API.

    Args:
        channel_id: Slack channel ID (e.g., "C08LVA9E1SS")
        thread_ts: Thread timestamp (e.g., "1704897000.123456")
        output_path: Path to write JSON output
        xoxc_token: Slack xoxc token (or from env SLACK_MCP_XOXC_TOKEN)
        xoxd_token: Slack xoxd token (or from env SLACK_MCP_XOXD_TOKEN)
        workspace: Slack workspace name

    Returns:
        List of thread reply dicts

    Raises:
        RuntimeError: If API call fails
        ValueError: If authentication tokens are missing
    """
    # Get tokens from environment if not provided
    xoxc = xoxc_token or os.getenv('SLACK_MCP_XOXC_TOKEN')
    xoxd = xoxd_token or os.getenv('SLACK_MCP_XOXD_TOKEN')

    if not xoxc or not xoxd:
        raise ValueError(
            "SLACK_MCP_XOXC_TOKEN and SLACK_MCP_XOXD_TOKEN must be set"
        )

    print(
        f"Fetching thread replies from channel {channel_id}, "
        f"thread {thread_ts}...",
        file=sys.stderr
    )

    url = "https://slack.com/api/conversations.replies"
    headers = {
        "Authorization": f"Bearer {xoxc}",
        "Cookie": f"d={xoxd}",
        "Content-Type": "application/json",
    }

    replies = []
    cursor = None
    page = 0

    while True:
        params = {
            "channel": channel_id,
            "ts": thread_ts,
            "limit": 200,
        }
        if cursor:
            params["cursor"] = cursor

        page += 1
        print(f"  Fetching page {page}...", file=sys.stderr)

        try:
            resp = requests.get(
                url, headers=headers, params=params, timeout=30
            )
            resp.raise_for_status()
        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"Slack API request failed: {e}") from e

        data = resp.json()
        if not data.get("ok"):
            error = data.get("error", "unknown")
            if error in ("invalid_auth", "token_revoked", "not_authed"):
                raise ValueError(f"Authentication failed: {error}")
            raise RuntimeError(f"Slack API error: {error}")

        batch = data.get("messages", [])
        replies.extend(batch)

        # Check for pagination
        metadata = data.get("response_metadata", {})
        cursor = metadata.get("next_cursor")
        if not cursor:
            break

        time.sleep(1)

    print(
        f"Fetched {len(replies)} replies",
        file=sys.stderr
    )

    with open(output_path, 'w') as f:
        json.dump(replies, f, indent=2)

    print(f"Thread replies saved to {output_path}", file=sys.stderr)

    return replies


def main() -> int:
    """Main entry point.

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    parser = argparse.ArgumentParser(
        description='Fetch Slack thread replies'
    )
    parser.add_argument(
        'channel_id',
        help='Slack channel ID (e.g., C08LVA9E1SS)'
    )
    parser.add_argument(
        'thread_ts',
        help='Thread timestamp (e.g., 1704897000.123456)'
    )
    parser.add_argument(
        'output_path',
        help='Path to write JSON output'
    )

    args = parser.parse_args()

    # Fetch thread replies
    try:
        thread_data = fetch_thread_replies(
            args.channel_id,
            args.thread_ts,
            args.output_path
        )
        # Output to stdout
        print(json.dumps(thread_data))
        return 0
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        if 'token' in str(e).lower():
            return 4  # Authentication error
        return 1  # Invalid parameters
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2  # API error


if __name__ == '__main__':
    sys.exit(main())
