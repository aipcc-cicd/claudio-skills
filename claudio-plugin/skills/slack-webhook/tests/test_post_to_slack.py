"""Tests for post-to-slack.sh using a mock curl binary.

All tests are fully offline — the mock curl script intercepts every HTTP call
and returns canned responses. No real Slack messages are sent.
"""

import json
import os
import stat
import subprocess

import pytest

SCRIPT_DIR = os.path.join(os.path.dirname(__file__), "..", "scripts")
SCRIPT_PATH = os.path.join(SCRIPT_DIR, "post-to-slack.sh")
WEBHOOK_URL = "https://hooks.slack.com/services/T000/B000/xxxx"

# Mock jq implemented in Python — handles the two jq patterns used by the script:
#   jq -n --arg text MSG '{"text": $text}'
#   echo JSON | jq '{blocks: .}'
MOCK_JQ_SCRIPT = r"""#!/usr/bin/env python3
import json, sys

def main():
    args = sys.argv[1:]
    no_input = False
    variables = {}
    filter_expr = None

    i = 0
    while i < len(args):
        if args[i] == "-n":
            no_input = True
            i += 1
        elif args[i] == "--arg":
            variables[args[i+1]] = args[i+2]
            i += 3
        else:
            filter_expr = args[i]
            i += 1

    if no_input:
        data = None
    else:
        data = json.loads(sys.stdin.read())

    # '{"text": $text}' — build object from variable
    if filter_expr and "$text" in filter_expr and "text" in variables:
        print(json.dumps({"text": variables["text"]}))
    # '{blocks: .}' — wrap input in blocks key
    elif filter_expr and "blocks" in filter_expr and data is not None:
        print(json.dumps({"blocks": data}))
    else:
        print(json.dumps(data))

if __name__ == "__main__":
    main()
"""


def _create_mock_jq(tmp_path):
    """Create a mock jq script implemented in Python."""
    mock_script = tmp_path / "jq"
    mock_script.write_text(MOCK_JQ_SCRIPT)
    mock_script.chmod(mock_script.stat().st_mode | stat.S_IEXEC)


def _create_mock_curl(tmp_path, exit_code=0, http_code="200", body="ok"):
    """Create a mock curl script that logs calls and returns canned responses."""
    log_file = tmp_path / "curl_calls.log"
    mock_script = tmp_path / "curl"

    mock_content = f"""#!/usr/bin/env bash
# Mock curl - logs all args as a single JSON array per invocation
python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" "$@" >> "{log_file}"

OUTPUT_FILE=""
ARGS=("$@")
for ((i=0; i<${{#ARGS[@]}}; i++)); do
    if [[ "${{ARGS[$i]}}" == "-o" ]]; then
        OUTPUT_FILE="${{ARGS[$((i+1))]}}"
    fi
done

if [[ -n "$OUTPUT_FILE" ]]; then
    echo -n '{body}' > "$OUTPUT_FILE"
fi

# Handle -w format string — print the http code
printf '{http_code}'

exit {exit_code}
"""

    mock_script.write_text(mock_content)
    mock_script.chmod(mock_script.stat().st_mode | stat.S_IEXEC)
    return str(log_file)


def _run_script(tmp_path, args, env_extras=None):
    """Run post-to-slack.sh with mock curl and jq on PATH."""
    _create_mock_jq(tmp_path)
    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}:{env['PATH']}"
    env.pop("SLACK_WEBHOOK_URL", None)
    if env_extras:
        env.update(env_extras)

    result = subprocess.run(
        ["bash", SCRIPT_PATH] + args,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    return result


def _read_curl_log(log_file):
    """Read logged curl calls. Each invocation is a JSON array of args."""
    if not os.path.exists(log_file):
        return []
    with open(log_file) as f:
        return [json.loads(line) for line in f.readlines() if line.strip()]


# --- Argument validation tests ---


class TestArgValidation:
    def test_no_arguments(self, tmp_path):
        result = _run_script(tmp_path, [])
        assert result.returncode == 1
        assert "Usage:" in result.stderr

    def test_unknown_flag(self, tmp_path):
        result = _run_script(tmp_path, ["--foo"])
        assert result.returncode == 1
        assert "Unknown flag" in result.stderr

    def test_multiple_positional_args(self, tmp_path):
        result = _run_script(
            tmp_path,
            ["Hello", "World"],
            env_extras={"SLACK_WEBHOOK_URL": WEBHOOK_URL},
        )
        assert result.returncode == 1
        assert "too many arguments" in result.stderr

    def test_missing_webhook_url(self, tmp_path):
        result = _run_script(tmp_path, ["hello"])
        assert result.returncode == 1
        assert "SLACK_WEBHOOK_URL not set" in result.stderr


# --- --check flag tests ---


class TestCheckFlag:
    def test_check_with_url_set(self, tmp_path):
        result = _run_script(
            tmp_path,
            ["--check"],
            env_extras={"SLACK_WEBHOOK_URL": WEBHOOK_URL},
        )
        assert result.returncode == 0
        assert "OK" in result.stdout

    def test_check_without_url(self, tmp_path):
        result = _run_script(tmp_path, ["--check"])
        assert result.returncode == 1
        assert "SLACK_WEBHOOK_URL is not set" in result.stderr


# --- Successful POST tests ---


class TestSuccessfulPost:
    def test_plain_text_message(self, tmp_path):
        log_file = _create_mock_curl(tmp_path)
        result = _run_script(
            tmp_path,
            ["Build completed"],
            env_extras={"SLACK_WEBHOOK_URL": WEBHOOK_URL},
        )
        assert result.returncode == 0
        assert "successfully" in result.stdout

        calls = _read_curl_log(log_file)
        assert len(calls) == 1
        args = calls[0]
        assert WEBHOOK_URL in args
        d_index = args.index("-d")
        payload = json.loads(args[d_index + 1])
        assert payload == {"text": "Build completed"}

    def test_blocks_with_valid_json(self, tmp_path):
        log_file = _create_mock_curl(tmp_path)
        blocks = [{"type": "section", "text": {"type": "mrkdwn", "text": "hello"}}]
        result = _run_script(
            tmp_path,
            ["--blocks", json.dumps(blocks)],
            env_extras={"SLACK_WEBHOOK_URL": WEBHOOK_URL},
        )
        assert result.returncode == 0
        assert "successfully" in result.stdout

        calls = _read_curl_log(log_file)
        assert len(calls) == 1
        args = calls[0]
        d_index = args.index("-d")
        payload = json.loads(args[d_index + 1])
        assert payload == {"blocks": blocks}


# --- Error handling tests ---


class TestErrorHandling:
    def test_blocks_with_invalid_json(self, tmp_path):
        result = _run_script(
            tmp_path,
            ["--blocks", "not-json"],
            env_extras={"SLACK_WEBHOOK_URL": WEBHOOK_URL},
        )
        assert result.returncode == 1
        assert "invalid Block Kit JSON" in result.stderr

    def test_webhook_non_200_response(self, tmp_path):
        _create_mock_curl(tmp_path, http_code="403", body="invalid_token")
        result = _run_script(
            tmp_path,
            ["test message"],
            env_extras={"SLACK_WEBHOOK_URL": WEBHOOK_URL},
        )
        assert result.returncode == 2
        assert "HTTP 403" in result.stderr

    def test_curl_network_failure(self, tmp_path):
        _create_mock_curl(tmp_path, exit_code=7, http_code="000", body="connection refused")
        result = _run_script(
            tmp_path,
            ["test message"],
            env_extras={"SLACK_WEBHOOK_URL": WEBHOOK_URL},
        )
        assert result.returncode == 2
        assert "curl failed" in result.stderr
