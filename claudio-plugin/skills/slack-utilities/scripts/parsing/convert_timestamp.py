#!/usr/bin/env python3
"""Convert Slack timestamp to ISO 8601 format.

This script converts Slack's Unix timestamp format (with microseconds)
to ISO 8601 format with UTC timezone.

Exit Codes:
    0: Success
    1: Invalid parameters
    3: Parsing error
"""

import argparse
import sys
from datetime import datetime, timezone


def convert_timestamp(slack_ts: str) -> str:
    """Convert Slack timestamp to ISO 8601 format.

    Args:
        slack_ts: Slack timestamp (e.g., "1704897000.123456")

    Returns:
        ISO 8601 timestamp (e.g., "2025-01-10T15:30:00Z")

    Raises:
        ValueError: If timestamp format is invalid
    """
    # Validate format (must be numeric with optional decimal)
    try:
        # Extract Unix timestamp (integer part before decimal)
        unix_ts = int(float(slack_ts))
    except (ValueError, TypeError) as e:
        raise ValueError(f"Invalid Slack timestamp format: {slack_ts}") from e

    # Convert to datetime in UTC
    try:
        dt = datetime.fromtimestamp(unix_ts, tz=timezone.utc)
        # Format as ISO 8601
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    except (ValueError, OSError) as e:
        raise ValueError(f"Failed to convert timestamp {slack_ts}: {e}") from e


def main() -> int:
    """Main entry point.

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    parser = argparse.ArgumentParser(
        description='Convert Slack timestamp to ISO 8601 format'
    )
    parser.add_argument(
        'slack_ts',
        help='Slack timestamp (e.g., "1704897000.123456")'
    )

    args = parser.parse_args()

    # Convert timestamp
    try:
        iso_ts = convert_timestamp(args.slack_ts)
        print(iso_ts)
        return 0
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 3  # Parsing error


if __name__ == '__main__':
    sys.exit(main())
