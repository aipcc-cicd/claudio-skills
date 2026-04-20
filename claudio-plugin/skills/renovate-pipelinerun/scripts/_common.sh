#!/usr/bin/env bash
#
# Common helpers for renovate-pipelinerun scripts.
# Sourced by all scripts in this directory.
#
# Environment variables:
#   RENOVATE_NAMESPACE - OpenShift namespace (default: rhel-ai-cicd--renovate-runner)

set -euo pipefail

_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TOOLS_DIR="$_COMMON_DIR/../../../tools"

RENOVATE_NAMESPACE="${RENOVATE_NAMESPACE:-rhel-ai-cicd--renovate-runner}"
export RENOVATE_NAMESPACE

die() { echo "{\"error\": \"$1\"}"; exit "${2:-1}"; }

ensure_auth() {
    command -v kubectl >/dev/null 2>&1 || "$_TOOLS_DIR/kubectl/install.sh"
    command -v tkn >/dev/null 2>&1 || "$_TOOLS_DIR/tkn/install.sh"
    kubectl auth whoami >/dev/null 2>&1 || die "Not authenticated to the cluster. Run: oc login <cluster-url> or configure kubectl"
    kubectl get namespace "$RENOVATE_NAMESPACE" >/dev/null 2>&1 || die "Namespace '$RENOVATE_NAMESPACE' not found on the cluster."
}

# Check if a pipeline has active (non-terminal) TaskRuns.
# Returns 0 if busy, 1 if idle. Prints JSON either way.
check_busy() {
    local pipeline_name="$1"
    local pipelineruns
    pipelineruns=$(tkn pipelinerun list -n "$RENOVATE_NAMESPACE" \
        -o jsonpath='{range .items[*]}{.metadata.labels.tekton\.dev/pipeline}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | grep "^${pipeline_name} " | head -10 | cut -d' ' -f2)

    for pr in $pipelineruns; do
        [ -z "$pr" ] && continue
        local active
        active=$(tkn taskrun list -n "$RENOVATE_NAMESPACE" \
            --label "tekton.dev/pipelineRun=${pr}" \
            -o jsonpath='{range .items[*]}{.status.conditions[0].reason}{"\n"}{end}' 2>/dev/null \
            | grep -cvE "^(Succeeded|Failed|TaskRunCancelled|TaskRunTimeout)$" 2>/dev/null || true)
        active=${active:-0}
        if [ "$active" -gt 0 ]; then
            echo "{\"busy\": true, \"pipelinerun\": \"$pr\", \"active_taskruns\": $active}"
            return 0
        fi
    done
    echo '{"busy": false}'
    return 1
}
