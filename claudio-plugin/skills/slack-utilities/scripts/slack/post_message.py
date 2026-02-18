#!/usr/bin/env python3
"""Post message to Slack channel using Slack API.

This script posts messages to Slack channels with proper
error handling and response validation.

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
from typing import Optional

import requests


def post_message(
    channel_id: str,
    message_text: str,
    xoxc_token: Optional[str] = None
) -> dict:
    """Post message to Slack channel using Slack API.

    Args:
        channel_id: Slack channel ID (e.g., "C09G0CMTUNA")
        message_text: Message text to post
        xoxc_token: Slack xoxc token (or from env SLACK_MCP_XOXC_TOKEN)

    Returns:
        API response as dictionary

    Raises:
        RuntimeError: If API call fails
        ValueError: If authentication token is missing
    """
    # Get token from environment if not provided
    token = xoxc_token or os.getenv('SLACK_MCP_XOXC_TOKEN')

    if not token:
        raise ValueError("SLACK_MCP_XOXC_TOKEN must be set")

    print(f"Posting message to channel {channel_id}...", file=sys.stderr)

    # Prepare request
    url = "https://slack.com/api/chat.postMessage"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    payload = {
        "channel": channel_id,
        "text": message_text,
    }

    # Make API call
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        raise RuntimeError(f"Failed to post message: {e}") from e

    # Parse response
    try:
        data = response.json()
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Invalid JSON response: {e}") from e

    # Check if API call succeeded
    if not data.get('ok'):
        error = data.get('error', 'Unknown error')
        raise RuntimeError(f"Slack API error: {error}")

    print("Message posted successfully", file=sys.stderr)
    return data


def main() -> int:
    """Main entry point.

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    parser = argparse.ArgumentParser(
        description='Post message to Slack channel using Slack API'
    )
    parser.add_argument(
        'channel_id',
        help='Slack channel ID (e.g., C09G0CMTUNA for #forum-claudio)'
    )
    parser.add_argument(
        'message_text',
        help='Message text to post'
    )

    args = parser.parse_args()

    # Post message
    try:
        response = post_message(args.channel_id, args.message_text)
        # Output response to stdout
        print(json.dumps(response))
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
