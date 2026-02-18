"""Unit tests for parsing scripts."""

import pytest
from unittest.mock import patch
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts' / 'parsing'))

from convert_timestamp import convert_timestamp, main as convert_timestamp_main


class TestConvertTimestamp:
    """Tests for convert_timestamp module."""

    @pytest.mark.parametrize("slack_ts, expected", [
        ("1704897000.123456", "2024-01-10T14:30:00Z"),
        ("1704897000", "2024-01-10T14:30:00Z"),  # without microseconds
    ])
    def test_convert_timestamp_valid(self, slack_ts, expected):
        assert convert_timestamp(slack_ts) == expected

    @pytest.mark.parametrize("slack_ts, match", [
        ("not-a-timestamp", "Invalid Slack timestamp"),
        ("999999999999999", ""),  # out of range
        (None, "Invalid Slack timestamp"),
        ("", "Invalid Slack timestamp"),
    ])
    def test_convert_timestamp_invalid(self, slack_ts, match):
        with pytest.raises(ValueError, match=match):
            convert_timestamp(slack_ts)


# --- CLI main() function tests ---


class TestConvertTimestampMain:
    """Tests for convert_timestamp main() CLI entry point."""

    @pytest.mark.parametrize("argv, exit_code", [
        (['convert_timestamp.py', '1704897000.123456'], 0),
        (['convert_timestamp.py', 'not-a-timestamp'], 3),
    ])
    def test_main(self, argv, exit_code):
        with patch('sys.argv', argv):
            assert convert_timestamp_main() == exit_code
