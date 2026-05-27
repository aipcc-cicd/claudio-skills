#!/usr/bin/env bash
# Posts a message to Slack via incoming webhook.
# Usage: post-to-slack.sh [--check] [--blocks] "<message_or_json>"

set -euo pipefail

EXIT_INVALID_PARAMS=1
EXIT_API_ERROR=2

response_file=""
cleanup() { [[ -n "$response_file" ]] && rm -f "$response_file" || true; }
trap cleanup EXIT

use_blocks=false
check_only=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)  check_only=true; shift ;;
        --blocks) use_blocks=true; shift ;;
        --)       shift; break ;;
        -*)       echo "Unknown flag: $1" >&2; exit "$EXIT_INVALID_PARAMS" ;;
        *)        break ;;
    esac
done

webhook_url="${SLACK_WEBHOOK_URL:-}"

if "$check_only"; then
    if [[ -n "$webhook_url" ]]; then
        echo "OK: SLACK_WEBHOOK_URL is set"
        exit 0
    else
        echo "SLACK_WEBHOOK_URL is not set" >&2
        exit "$EXIT_INVALID_PARAMS"
    fi
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [--check] [--blocks] '<message_or_json>'" >&2
    exit "$EXIT_INVALID_PARAMS"
fi

if [[ $# -gt 1 ]]; then
    echo "Error: too many arguments (did you forget to quote the message?)" >&2
    echo "Usage: $0 [--check] [--blocks] '<message_or_json>'" >&2
    exit "$EXIT_INVALID_PARAMS"
fi

message="$1"

if [[ -z "$webhook_url" ]]; then
    echo "Error: SLACK_WEBHOOK_URL not set" >&2
    exit "$EXIT_INVALID_PARAMS"
fi

if "$use_blocks"; then
    if ! payload=$(echo "$message" | jq '{blocks: .}' 2>&1); then
        echo "Error: invalid Block Kit JSON: $payload" >&2
        exit "$EXIT_INVALID_PARAMS"
    fi
else
    payload=$(jq -n --arg text "$message" '{"text": $text}')
fi

response_file=$(mktemp /tmp/slack-webhook-XXXXXX.txt)

set +e
http_code=$(curl --silent --show-error \
    --connect-timeout 10 --max-time 30 \
    -o "$response_file" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$webhook_url" 2>>"$response_file")
curl_rc=$?
set -e

if [[ $curl_rc -ne 0 ]]; then
    echo "curl failed (exit $curl_rc): $(cat "$response_file")" >&2
    exit "$EXIT_API_ERROR"
fi

if [[ "$http_code" != "200" ]]; then
    echo "Slack webhook returned HTTP $http_code: $(cat "$response_file")" >&2
    exit "$EXIT_API_ERROR"
fi

echo "Message posted successfully"
