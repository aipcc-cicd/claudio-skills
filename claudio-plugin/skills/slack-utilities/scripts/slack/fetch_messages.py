#!/usr/bin/env python3
"""Fetch Slack channel message history using Slack Web API.

This script fetches channel history using direct Slack API calls
with proper time window conversion and error handling.

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
from datetime import datetime, timedelta, timezone
from typing import Optional

import requests


def parse_time_window(time_window: str) -> str:
    """Convert time window to ISO 8601 date string.

    Args:
        time_window: Time window (e.g., "65m", "90d", "1w")

    Returns:
        ISO 8601 date string (e.g., "2025-10-20T00:00:00")

    Raises:
        ValueError: If time window format is invalid
    """
    if not time_window:
        raise ValueError("Time window cannot be empty")

    unit = time_window[-1]
    try:
        value = int(time_window[:-1])
    except (IndexError, ValueError):
        raise ValueError(f"Invalid time window format: {time_window}")

    # Map unit to timedelta kwargs
    unit_map = {
        'm': {'minutes': value},
        'h': {'hours': value},
        'd': {'days': value},
        'w': {'weeks': value},
    }

    if unit not in unit_map:
        raise ValueError(
            f"Invalid time window unit '{unit}'. Use: m, h, d, w"
        )

    oldest = datetime.now(timezone.utc) - timedelta(**unit_map[unit])
    return oldest.strftime('%Y-%m-%dT%H:%M:%S')


def filter_messages_by_date(messages: list, target_date: str) -> list:
    """Filter messages to only those from a specific date (UTC).

    Args:
        messages: List of Slack message dicts (must have 'ts' field)
        target_date: Date string in YYYY-MM-DD format

    Returns:
        List of messages from the target date
    """
    filtered = []
    for msg in messages:
        ts = msg.get('ts')
        if not ts:
            continue
        try:
            unix_ts = int(float(ts))
            msg_date = datetime.fromtimestamp(
                unix_ts, tz=timezone.utc
            ).strftime('%Y-%m-%d')
            if msg_date == target_date:
                filtered.append(msg)
        except (ValueError, TypeError, OSError):
            continue
    return filtered


def fetch_messages_api(
    channel_id: str,
    oldest_ts: float,
    latest_ts: float,
    xoxc_token: str,
    xoxd_token: str,
) -> list:
    """Fetch messages using Slack Web API directly.

    Makes minimal API calls (1 per 200 messages) with pagination.

    Args:
        channel_id: Slack channel ID
        oldest_ts: Unix timestamp for oldest message
        latest_ts: Unix timestamp for latest message
        xoxc_token: Slack xoxc token (used as Bearer token)
        xoxd_token: Slack xoxd token (used as cookie)

    Returns:
        List of message dicts
    """
    url = "https://slack.com/api/conversations.history"
    headers = {
        "Authorization": f"Bearer {xoxc_token}",
        "Cookie": f"d={xoxd_token}",
        "Content-Type": "application/json",
    }

    messages = []
    cursor = None
    page = 0

    while True:
        params = {
            "channel": channel_id,
            "oldest": str(oldest_ts),
            "latest": str(latest_ts),
            "limit": 200,
        }
        if cursor:
            params["cursor"] = cursor

        page += 1
        print(
            f"  Fetching page {page}...",
            file=sys.stderr
        )

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
        messages.extend(batch)

        # Check for pagination
        metadata = data.get("response_metadata", {})
        cursor = metadata.get("next_cursor")
        if not cursor:
            break

        # Small delay between pages to be gentle
        time.sleep(1)

    return messages


def fetch_messages(
    channel_id: str,
    time_window: str,
    output_path: str,
    xoxc_token: Optional[str] = None,
    xoxd_token: Optional[str] = None,
    workspace: str = "redhat"
) -> list:
    """Fetch Slack channel messages.

    Uses direct Slack API calls (1 call per 200 messages).

    Args:
        channel_id: Slack channel ID (e.g., "C08LVA9E1SS")
        time_window: Time window (e.g., "65m", "90d")
        output_path: Path to write JSON output
        xoxc_token: Slack xoxc token (or from env SLACK_MCP_XOXC_TOKEN)
        xoxd_token: Slack xoxd token (or from env SLACK_MCP_XOXD_TOKEN)
        workspace: Slack workspace name

    Returns:
        List of message dicts

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

    # Calculate time range
    oldest_iso = parse_time_window(time_window)
    oldest_dt = datetime.fromisoformat(oldest_iso).replace(tzinfo=timezone.utc)
    oldest_ts = oldest_dt.timestamp()
    latest_ts = datetime.now(timezone.utc).timestamp()

    print(
        f"Fetching messages from channel {channel_id} "
        f"(last {time_window}, from {oldest_iso})...",
        file=sys.stderr
    )

    messages = fetch_messages_api(
        channel_id, oldest_ts, latest_ts, xoxc, xoxd
    )

    print(
        f"Fetched {len(messages)} messages",
        file=sys.stderr
    )

    with open(output_path, 'w') as f:
        json.dump(messages, f, indent=2)

    print(f"Messages saved to {output_path}", file=sys.stderr)

    return messages


def main() -> int:
    """Main entry point.

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    parser = argparse.ArgumentParser(
        description='Fetch Slack channel message history'
    )
    parser.add_argument(
        'channel_id',
        help='Slack channel ID (e.g., C08LVA9E1SS)'
    )
    parser.add_argument(
        'time_window',
        help='Time window to fetch (e.g., 65m, 90d, 1w)'
    )
    parser.add_argument(
        'output_path',
        help='Path to write JSON output'
    )
    parser.add_argument(
        '--filter-date',
        help='Filter messages to this date only (YYYY-MM-DD). '
             'When set, only messages from this date are written to '
             'stdout and the output file.'
    )

    args = parser.parse_args()

    # Fetch messages
    try:
        messages = fetch_messages(
            args.channel_id,
            args.time_window,
            args.output_path
        )

        # Apply date filter if requested
        if args.filter_date:
            filtered = filter_messages_by_date(messages, args.filter_date)
            print(
                f"Filtered to {len(filtered)} messages from "
                f"{args.filter_date} (out of {len(messages)} total)",
                file=sys.stderr
            )
            # Overwrite output file with only filtered messages
            with open(args.output_path, 'w') as f:
                json.dump(filtered, f, indent=2)
            # Output filtered messages to stdout (small enough)
            print(json.dumps(filtered))
        else:
            # No filter: output summary only (full data is in the file)
            print(json.dumps({
                "message_count": len(messages),
                "output_path": args.output_path
            }))
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
