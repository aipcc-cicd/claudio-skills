#!/usr/bin/env python3
"""Find Slack channel ID by name using Slack Web API.

This script searches for a Slack channel by name and returns
its channel ID.

Exit Codes:
    0: Success
    1: Invalid parameters / channel not found
    2: API error
    4: Authentication error
"""

import argparse
import json
import os
import sys
from typing import Optional

import requests


def find_channel(
    channel_name: str,
    xoxc_token: Optional[str] = None,
    xoxd_token: Optional[str] = None
) -> dict:
    """Find Slack channel by name.

    Args:
        channel_name: Channel name to search for (without #)
        xoxc_token: Slack xoxc token (or from env SLACK_XOXC_TOKEN)
        xoxd_token: Slack xoxd token (or from env SLACK_XOXD_TOKEN)

    Returns:
        Channel info dict with id, name, is_private, num_members

    Raises:
        RuntimeError: If API call fails
        ValueError: If token missing or channel not found
    """
    xoxc = xoxc_token or os.getenv('SLACK_XOXC_TOKEN')
    xoxd = xoxd_token or os.getenv('SLACK_XOXD_TOKEN')

    if not xoxc or not xoxd:
        raise ValueError(
            "SLACK_XOXC_TOKEN and SLACK_XOXD_TOKEN must be set"
        )
    if not xoxc.startswith('xoxc-'):
        raise ValueError("SLACK_XOXC_TOKEN must start with 'xoxc-'")
    if not xoxd.startswith('xoxd-'):
        raise ValueError("SLACK_XOXD_TOKEN must start with 'xoxd-'")

    name = channel_name.lstrip('#')

    print(f"Searching for channel '{name}'...", file=sys.stderr)

    url = "https://slack.com/api/search.modules"
    headers = {
        "Authorization": f"Bearer {xoxc}",
        "Cookie": f"d={xoxd}",
        "Content-Type": "application/x-www-form-urlencoded",
    }

    try:
        resp = requests.post(
            url, headers=headers, data={
                "query": name,
                "module": "channels",
                "count": "10",
            }, timeout=30
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

    for item in data.get("items", []):
        ch = item.get("channel", item)
        if ch.get("name") == name:
            print(f"Found channel: {name} ({ch['id']})", file=sys.stderr)
            return {
                "id": ch["id"],
                "name": ch["name"],
                "is_private": ch.get("is_private", False),
                "num_members": ch.get("num_members", 0),
            }

    raise ValueError(f"Channel '{name}' not found")


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Find Slack channel ID by name'
    )
    parser.add_argument(
        'channel_name',
        help='Channel name to search for (with or without #)'
    )

    args = parser.parse_args()

    try:
        result = find_channel(args.channel_name)
        print(json.dumps(result))
        return 0
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        if 'token' in str(e).lower() or 'auth' in str(e).lower():
            return 4
        return 1
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
