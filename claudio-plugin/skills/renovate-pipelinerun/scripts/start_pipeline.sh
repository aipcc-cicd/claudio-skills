#!/usr/bin/env bash
#
# Start a Renovate PipelineRun on OpenShift.
# Usage: ./start_pipeline.sh <pipeline-name> [--force] [--dry-run]
# Exit codes: 0=started, 1=error, 2=busy

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

PIPELINE_NAME=""
FORCE=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force) FORCE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -*) die "Unknown option: $1. Usage: start_pipeline.sh <pipeline-name> [--force] [--dry-run]" ;;
        *)  PIPELINE_NAME="$1"; shift ;;
    esac
done
[[ -n "$PIPELINE_NAME" ]] || die "Pipeline name is required. Usage: start_pipeline.sh <pipeline-name> [--force] [--dry-run]"

ensure_auth

# Validate pipeline exists (fetch list once)
available=$(tkn pipeline list -n "$RENOVATE_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^renovate-" | sort)
echo "$available" | grep -qx "$PIPELINE_NAME" || die "Pipeline '$PIPELINE_NAME' not found. Available: $(echo $available | tr ' ' ',')"

# Busy check
busy_result=$(check_busy "$PIPELINE_NAME") && is_busy=true || is_busy=false
if [[ "$is_busy" = true && "$FORCE" = false ]]; then
    echo "$busy_result" | jq --arg p "$PIPELINE_NAME" '. + {error: "Pipeline is busy. Use --force to start anyway.", pipeline: $p}'
    exit 2
fi

# Build tkn command
tkn_args=(pipeline start "$PIPELINE_NAME" -n "$RENOVATE_NAMESPACE"
    --serviceaccount renovate-admin --use-param-defaults
    --pipeline-timeout 2h -w name=shared-workspace,emptyDir="")
[[ "$DRY_RUN" = true ]] && tkn_args+=(--dry-run -o yaml)

output=$(tkn "${tkn_args[@]}" 2>&1)

if [[ "$DRY_RUN" = true ]]; then
    echo "$output"
else
    pipelinerun_name=$(echo "$output" | grep -oP 'PipelineRun started: \K\S+' || true)
    [[ -n "$pipelinerun_name" ]] || die "Failed to start PipelineRun. Output: $output"
    echo "{\"status\": \"started\", \"pipeline\": \"$PIPELINE_NAME\", \"pipelinerun\": \"$pipelinerun_name\", \"namespace\": \"$RENOVATE_NAMESPACE\"}"
fi
