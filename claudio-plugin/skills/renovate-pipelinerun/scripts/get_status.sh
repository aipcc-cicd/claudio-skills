#!/usr/bin/env bash
#
# Get PipelineRun status or recent history.
# Usage:
#   ./get_status.sh <name>              # Status of a PipelineRun or most recent run for a pipeline
#   ./get_status.sh <name> --history N  # List last N PipelineRuns for a pipeline
#   ./get_status.sh --all [--history N] # Recent runs across all Renovate pipelines

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

NAME=""
HISTORY_COUNT=""
ALL_PIPELINES=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --history) HISTORY_COUNT="${2:-10}"; shift 2 ;;
        --all) ALL_PIPELINES=true; shift ;;
        -*) die "Unknown option: $1" ;;
        *)  NAME="$1"; shift ;;
    esac
done
[[ -n "$NAME" || "$ALL_PIPELINES" = true ]] || die "Name or --all is required. Usage: get_status.sh <name> [--history N] or get_status.sh --all"

ensure_auth

# --- History mode ---
list_history() {
    local filter="$1" count="${HISTORY_COUNT:-10}"
    local raw
    raw=$(tkn pipelinerun list -n "$RENOVATE_NAMESPACE" --limit "$count" \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.tekton\.dev/pipeline}{"\t"}{.status.startTime}{"\t"}{.status.completionTime}{"\t"}{.status.conditions[0].reason}{"\n"}{end}' 2>/dev/null)

    if [[ "$filter" = "--all" ]]; then
        raw=$(echo "$raw" | grep "	renovate-" || true)
    else
        raw=$(echo "$raw" | grep "	${filter}	" || true)
    fi

    echo "$raw" | jq -Rn '[inputs | select(length > 0) | split("\t") | {name:.[0], pipeline:.[1], start_time:.[2], completion_time:(.[3] // "running"), status:(.[4] // "Unknown")}] | {runs:., count:length}'
}

# --- Detail mode ---
show_detail() {
    local pr_name="$1"
    local pr_json
    pr_json=$(tkn pipelinerun describe "$pr_name" -n "$RENOVATE_NAMESPACE" -o json 2>/dev/null) || die "PipelineRun '$pr_name' not found"

    echo "$pr_json" | jq '{
        pipelinerun: .metadata.name,
        pipeline: .metadata.labels["tekton.dev/pipeline"],
        start_time: .status.startTime,
        completion_time: .status.completionTime,
        status: .status.conditions[0].reason,
        message: .status.conditions[0].message,
        tasks: [.status.childReferences[]? | {name: .pipelineTaskName, taskrun: .name}]
    }'
}

# --- Route ---
if [[ -n "$HISTORY_COUNT" || "$ALL_PIPELINES" = true ]]; then
    if [[ "$ALL_PIPELINES" = true ]]; then
        list_history "--all"
    else
        list_history "$NAME"
    fi
elif tkn pipelinerun describe "$NAME" -n "$RENOVATE_NAMESPACE" -o json >/dev/null 2>&1; then
    show_detail "$NAME"
else
    latest=$(tkn pipelinerun list -n "$RENOVATE_NAMESPACE" \
        -o jsonpath='{range .items[*]}{.metadata.labels.tekton\.dev/pipeline}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | grep "^${NAME} " | head -1 | cut -d' ' -f2)
    [[ -n "$latest" ]] || die "No PipelineRuns found for pipeline '$NAME'"
    show_detail "$latest"
fi
