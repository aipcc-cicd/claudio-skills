#!/usr/bin/env bash
#
# Retrieve logs from a PipelineRun or TaskRun.
# Usage: ./get_logs.sh <name> [--lines N]

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

NAME=""
LINES=200
while [[ $# -gt 0 ]]; do
    case $1 in
        --lines) LINES="${2:-200}"; shift 2 ;;
        -*) die "Unknown option: $1. Usage: get_logs.sh <name> [--lines N]" ;;
        *)  NAME="$1"; shift ;;
    esac
done
[[ -n "$NAME" ]] || die "Name is required. Usage: get_logs.sh <pipelinerun-or-taskrun-name> [--lines N]"

ensure_auth

# Try pipelinerun logs first, fall back to taskrun logs
if tkn pipelinerun logs "$NAME" -n "$RENOVATE_NAMESPACE" >/dev/null 2>&1; then
    echo "--- Logs for PipelineRun: $NAME (last $LINES lines) ---"
    tkn pipelinerun logs "$NAME" -n "$RENOVATE_NAMESPACE" 2>&1 | tail -n "$LINES"
elif tkn taskrun logs "$NAME" -n "$RENOVATE_NAMESPACE" >/dev/null 2>&1; then
    echo "--- Logs for TaskRun: $NAME (last $LINES lines) ---"
    tkn taskrun logs "$NAME" -n "$RENOVATE_NAMESPACE" 2>&1 | tail -n "$LINES"
else
    die "'$NAME' not found as a PipelineRun or TaskRun in namespace '$RENOVATE_NAMESPACE'"
fi
