"""Unit tests for Slack scripts."""

import json
import pytest
from unittest.mock import Mock, mock_open, patch
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts' / 'slack'))

from fetch_messages import parse_time_window, fetch_messages, filter_messages_by_date, main as fetch_messages_main
from fetch_thread_replies import fetch_thread_replies, main as fetch_thread_replies_main
from post_message import post_message, main as post_message_main


class TestParseTimeWindow:
    """Tests for parse_time_window function."""

    @pytest.mark.parametrize("window", ["65m", "2h"])
    def test_parse_time_window_returns_iso8601(self, window):
        result = parse_time_window(window)
        assert len(result) == 19  # YYYY-MM-DDTHH:MM:SS
        assert "T" in result

    def test_parse_time_window_days(self):
        from datetime import datetime, timedelta, timezone
        result = parse_time_window("90d")
        expected = datetime.now(timezone.utc) - timedelta(days=90)
        assert result.startswith(expected.strftime('%Y-%m-%d'))

    def test_parse_time_window_weeks(self):
        from datetime import datetime, timedelta, timezone
        result = parse_time_window("1w")
        expected = datetime.now(timezone.utc) - timedelta(weeks=1)
        assert result.startswith(expected.strftime('%Y-%m-%d'))

    @pytest.mark.parametrize("window, match", [
        ("5x", "Invalid time window unit"),
        ("", "cannot be empty"),
        ("m", "Invalid time window format"),
        ("abcd", "Invalid time window format"),
    ])
    def test_parse_time_window_invalid(self, window, match):
        with pytest.raises(ValueError, match=match):
            parse_time_window(window)


class TestFilterMessagesByDate:
    """Tests for filter_messages_by_date function."""

    def test_filter_matches_target_date(self):
        messages = [
            {"ts": "1734256800.000000", "text": "Dec 15 msg"},  # 2024-12-15
            {"ts": "1734343200.000000", "text": "Dec 16 msg"},
            {"ts": "1734170400.000000", "text": "Dec 14 msg"},
        ]
        result = filter_messages_by_date(messages, "2024-12-15")
        assert len(result) == 1
        assert result[0]["text"] == "Dec 15 msg"

    def test_filter_no_matches(self):
        messages = [{"ts": "1734343200.000000", "text": "Dec 16 msg"}]
        assert len(filter_messages_by_date(messages, "2024-12-15")) == 0

    @pytest.mark.parametrize("messages, expected_count", [
        ([{"text": "no timestamp"}, {"ts": "1734256800.000000", "text": "has ts"}], 1),
        ([], 0),
        ([{"ts": "not-a-number", "text": "bad"}, {"ts": "1734256800.000000", "text": "good"}], 1),
        ([{"ts": None, "text": "null ts"}], 0),
    ])
    def test_filter_edge_cases(self, messages, expected_count):
        result = filter_messages_by_date(messages, "2024-12-15")
        assert len(result) == expected_count


class TestFetchMessages:
    """Tests for fetch_messages function."""

    @patch('fetch_messages.requests.get')
    @patch('fetch_messages.json.dump')
    def test_fetch_messages_success(self, mock_dump, mock_get):
        """Test successful message fetching via Slack Web API."""
        sample_messages = [{"text": "test", "ts": "1234567890"}]
        mock_response = Mock()
        mock_response.json.return_value = {
            "ok": True, "messages": sample_messages, "response_metadata": {},
        }
        mock_response.raise_for_status = Mock()
        mock_get.return_value = mock_response

        result = fetch_messages(
            channel_id="C123", time_window="65m", output_path="/tmp/test.json",
            xoxc_token="xoxc-test", xoxd_token="xoxd-test",
        )

        assert result == sample_messages
        mock_get.assert_called_once()
        call_kwargs = mock_get.call_args
        assert "Bearer xoxc-test" in call_kwargs.kwargs["headers"]["Authorization"]
        assert "xoxd-test" in call_kwargs.kwargs["headers"]["Cookie"]

    @pytest.mark.parametrize("error_code, exc_type, match", [
        ("channel_not_found", RuntimeError, "Slack API error"),
        ("invalid_auth", ValueError, "Authentication failed"),
    ])
    @patch('fetch_messages.requests.get')
    def test_fetch_messages_api_errors(self, mock_get, error_code, exc_type, match):
        mock_response = Mock()
        mock_response.json.return_value = {"ok": False, "error": error_code}
        mock_response.raise_for_status = Mock()
        mock_get.return_value = mock_response

        with pytest.raises(exc_type, match=match):
            fetch_messages(
                channel_id="C123", time_window="65m", output_path="/tmp/test.json",
                xoxc_token="xoxc-test", xoxd_token="xoxd-test",
            )

    @patch('fetch_messages.requests.get')
    @patch('fetch_messages.json.dump')
    def test_fetch_messages_pagination(self, mock_dump, mock_get):
        """Test pagination through multiple pages of results."""
        page1 = Mock()
        page1.json.return_value = {
            "ok": True, "messages": [{"text": "msg1", "ts": "1"}],
            "response_metadata": {"next_cursor": "cursor123"},
        }
        page1.raise_for_status = Mock()

        page2 = Mock()
        page2.json.return_value = {
            "ok": True, "messages": [{"text": "msg2", "ts": "2"}],
            "response_metadata": {},
        }
        page2.raise_for_status = Mock()

        mock_get.side_effect = [page1, page2]

        with patch('fetch_messages.time.sleep'):
            result = fetch_messages(
                channel_id="C123", time_window="65m", output_path="/tmp/test.json",
                xoxc_token="xoxc-test", xoxd_token="xoxd-test",
            )

        assert len(result) == 2
        assert mock_get.call_count == 2

    def test_fetch_messages_missing_tokens(self):
        with pytest.raises(ValueError, match="SLACK_MCP.*must be set"):
            fetch_messages(channel_id="C123", time_window="65m", output_path="/tmp/test.json")

    @patch('fetch_messages.requests.get')
    def test_fetch_messages_network_error(self, mock_get):
        import requests
        mock_get.side_effect = requests.exceptions.ConnectionError("Network error")

        with pytest.raises(RuntimeError, match="Slack API request failed"):
            fetch_messages(
                channel_id="C123", time_window="65m", output_path="/tmp/test.json",
                xoxc_token="xoxc-test", xoxd_token="xoxd-test",
            )


class TestFetchThreadReplies:
    """Tests for fetch_thread_replies function."""

    @patch('fetch_thread_replies.requests.get')
    @patch('fetch_thread_replies.json.dump')
    def test_fetch_thread_replies_success(self, mock_dump, mock_get):
        sample_thread = [{"text": "reply", "ts": "1234567891"}]
        mock_response = Mock()
        mock_response.json.return_value = {
            "ok": True, "messages": sample_thread, "response_metadata": {},
        }
        mock_response.raise_for_status = Mock()
        mock_get.return_value = mock_response

        result = fetch_thread_replies(
            channel_id="C123", thread_ts="1234567890.000000",
            output_path="/tmp/thread.json",
            xoxc_token="xoxc-test", xoxd_token="xoxd-test",
        )

        assert result == sample_thread
        assert mock_get.call_args.kwargs["params"]["ts"] == "1234567890.000000"

    @pytest.mark.parametrize("error_code, exc_type, match", [
        ("thread_not_found", RuntimeError, "Slack API error"),
        ("invalid_auth", ValueError, "Authentication failed"),
    ])
    @patch('fetch_thread_replies.requests.get')
    def test_fetch_thread_replies_api_errors(self, mock_get, error_code, exc_type, match):
        mock_response = Mock()
        mock_response.json.return_value = {"ok": False, "error": error_code}
        mock_response.raise_for_status = Mock()
        mock_get.return_value = mock_response

        with pytest.raises(exc_type, match=match):
            fetch_thread_replies(
                channel_id="C123", thread_ts="1234567890.000000",
                output_path="/tmp/thread.json",
                xoxc_token="xoxc-test", xoxd_token="xoxd-test",
            )

    def test_fetch_thread_replies_missing_tokens(self):
        with pytest.raises(ValueError, match="SLACK_MCP.*must be set"):
            fetch_thread_replies(
                channel_id="C123", thread_ts="1234567890.000000",
                output_path="/tmp/thread.json",
            )

    @patch('fetch_thread_replies.requests.get')
    def test_fetch_thread_replies_network_error(self, mock_get):
        import requests
        mock_get.side_effect = requests.exceptions.ConnectionError("Network error")

        with pytest.raises(RuntimeError, match="Slack API request failed"):
            fetch_thread_replies(
                channel_id="C123", thread_ts="1234567890.000000",
                output_path="/tmp/thread.json",
                xoxc_token="xoxc-test", xoxd_token="xoxd-test",
            )


class TestPostMessage:
    """Tests for post_message function."""

    @patch('post_message.requests.post')
    def test_post_message_success(self, mock_post):
        mock_response = Mock()
        mock_response.json.return_value = {"ok": True, "ts": "1234567890"}
        mock_response.raise_for_status = Mock()
        mock_post.return_value = mock_response

        result = post_message(channel_id="C123", message_text="Test", xoxc_token="xoxc-test")
        assert result["ok"] is True
        assert "ts" in result

    @pytest.mark.parametrize("side_effect, exc_type, match", [
        (None, RuntimeError, "Slack API error"),  # API returns ok=False
        ("connection", RuntimeError, "Failed to post message"),  # network error
        ("bad_json", RuntimeError, "Invalid JSON response"),  # invalid JSON
    ])
    @patch('post_message.requests.post')
    def test_post_message_errors(self, mock_post, side_effect, exc_type, match):
        import requests
        if side_effect == "connection":
            mock_post.side_effect = requests.exceptions.ConnectionError("err")
        elif side_effect == "bad_json":
            mock_response = Mock()
            mock_response.json.side_effect = json.JSONDecodeError("err", "", 0)
            mock_response.raise_for_status = Mock()
            mock_post.return_value = mock_response
        else:
            mock_response = Mock()
            mock_response.json.return_value = {"ok": False, "error": "channel_not_found"}
            mock_response.raise_for_status = Mock()
            mock_post.return_value = mock_response

        with pytest.raises(exc_type, match=match):
            post_message(channel_id="C123", message_text="Test", xoxc_token="xoxc-test")

    def test_post_message_missing_token(self):
        with pytest.raises(ValueError, match="SLACK_MCP_XOXC_TOKEN must be set"):
            post_message(channel_id="C123", message_text="Test")


# --- CLI main() function tests ---


class TestFetchMessagesMain:
    """Tests for fetch_messages main() CLI entry point."""

    @patch('fetch_messages.fetch_messages')
    @patch('sys.argv', ['fetch_messages.py', 'C123', '65m', '/tmp/out.json'])
    def test_main_success(self, mock_fetch):
        mock_fetch.return_value = [{"text": "msg", "ts": "1"}]
        assert fetch_messages_main() == 0

    @patch('fetch_messages.fetch_messages')
    @patch('sys.argv', ['fetch_messages.py', 'C123', '65m', '/tmp/out.json',
                        '--filter-date', '2024-12-15'])
    def test_main_with_filter_date(self, mock_fetch):
        mock_fetch.return_value = [
            {"text": "match", "ts": "1734256800.000000"},
            {"text": "no match", "ts": "1734343200.000000"},
        ]
        with patch('builtins.open', mock_open()):
            with patch('fetch_messages.json.dump'):
                assert fetch_messages_main() == 0

    @pytest.mark.parametrize("side_effect, exit_code", [
        (ValueError("SLACK_MCP_XOXC_TOKEN must be set"), 4),
        (RuntimeError("Slack API error"), 2),
    ])
    @patch('sys.argv', ['fetch_messages.py', 'C123', '65m', '/tmp/out.json'])
    def test_main_errors(self, side_effect, exit_code):
        with patch('fetch_messages.fetch_messages') as mock_fetch:
            mock_fetch.side_effect = side_effect
            assert fetch_messages_main() == exit_code


class TestFetchThreadRepliesMain:
    """Tests for fetch_thread_replies main() CLI entry point."""

    @patch('fetch_thread_replies.fetch_thread_replies')
    @patch('sys.argv', ['fetch_thread_replies.py', 'C123', '1234567890.000000', '/tmp/out.json'])
    def test_main_success(self, mock_fetch):
        mock_fetch.return_value = [{"text": "reply", "ts": "1"}]
        assert fetch_thread_replies_main() == 0

    @pytest.mark.parametrize("side_effect, exit_code", [
        (ValueError("token missing"), 4),
        (RuntimeError("Slack API error"), 2),
    ])
    @patch('sys.argv', ['fetch_thread_replies.py', 'C123', '1234567890.000000', '/tmp/out.json'])
    def test_main_errors(self, side_effect, exit_code):
        with patch('fetch_thread_replies.fetch_thread_replies') as mock_fetch:
            mock_fetch.side_effect = side_effect
            assert fetch_thread_replies_main() == exit_code


class TestPostMessageMain:
    """Tests for post_message main() CLI entry point."""

    @patch('post_message.post_message')
    @patch('sys.argv', ['post_message.py', 'C123', 'Hello world'])
    def test_main_success(self, mock_post):
        mock_post.return_value = {"ok": True, "ts": "1234567890"}
        assert post_message_main() == 0

    @pytest.mark.parametrize("side_effect, exit_code", [
        (ValueError("SLACK_MCP_XOXC_TOKEN must be set"), 4),
        (RuntimeError("Slack API error"), 2),
    ])
    @patch('sys.argv', ['post_message.py', 'C123', 'Hello'])
    def test_main_errors(self, side_effect, exit_code):
        with patch('post_message.post_message') as mock_post:
            mock_post.side_effect = side_effect
            assert post_message_main() == exit_code
