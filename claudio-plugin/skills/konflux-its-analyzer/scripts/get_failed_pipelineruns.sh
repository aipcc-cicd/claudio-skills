#!/usr/bin/env bash
#
# Get Failed ITS PipelineRuns
#
# Lists failed Konflux integration test scenario PipelineRuns from KubeArchive
# within a specified time period.
#
# Usage:
#   ./get_failed_pipelineruns.sh <namespace> <time-spec> [--human]
#
# Time specification formats:
#   2026-04-16              Single date
#   2026-04-14..2026-04-16  Date range
#   4h                      Last 4 hours
#   2d                      Last 2 days
#   1w                      Last week
#
# Environment variables:
#   KUBECONFIG       Path to kubeconfig file (required)
#   KUBEARCHIVE_HOST KubeArchive API server URL (required)
#
# Examples:
#   ./get_failed_pipelineruns.sh ai-tenant 2026-04-16
#   ./get_failed_pipelineruns.sh ai-tenant 2026-04-14..2026-04-16 --human
#   ./get_failed_pipelineruns.sh ai-tenant 4h

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    cat << 'EOF'
Usage: get_failed_pipelineruns.sh <namespace> <time-spec> [--human]

Arguments:
  namespace   Kubernetes namespace
  time-spec   Time period: YYYY-MM-DD, YYYY-MM-DD..YYYY-MM-DD, or Nh/Nd/Nw

Options:
  --human     Human-readable table output instead of JSON

Environment:
  KUBECONFIG        Path to kubeconfig file (required)
  KUBEARCHIVE_HOST  KubeArchive API server URL (required)
EOF
}

parse_time_spec() {
    local spec="$1"
    local start_ts end_ts

    if [[ "$spec" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\.\.[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        local start_date="${spec%..*}"
        local end_date="${spec#*..}"
        start_ts="${start_date}T00:00:00Z"
        end_ts="${end_date}T23:59:59Z"
    elif [[ "$spec" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        start_ts="${spec}T00:00:00Z"
        end_ts="${spec}T23:59:59Z"
    elif [[ "$spec" =~ ^([0-9]+)([hdw])$ ]]; then
        local amount="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        local seconds
        case "$unit" in
            h) seconds=$((amount * 3600)) ;;
            d) seconds=$((amount * 86400)) ;;
            w) seconds=$((amount * 604800)) ;;
        esac
        start_ts=$(date -u -d "@$(($(date +%s) - seconds))" +%Y-%m-%dT%H:%M:%SZ)
        end_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    else
        echo "ERROR: Invalid time-spec: $spec" >&2
        echo "Formats: YYYY-MM-DD, YYYY-MM-DD..YYYY-MM-DD, Nh, Nd, Nw" >&2
        exit 1
    fi

    echo "$start_ts $end_ts"
}

main() {
    local human=false

    if [[ $# -lt 2 ]]; then
        show_usage >&2
        exit 1
    fi

    local namespace="$1"
    local time_spec="$2"
    shift 2

    while [[ $# -gt 0 ]]; do
        case $1 in
            --human) human=true; shift ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                show_usage >&2
                exit 1
                ;;
        esac
    done

    if [ -z "${KUBECONFIG:-}" ]; then
        echo '{"error": "KUBECONFIG environment variable is not set"}' >&2
        exit 1
    fi

    if [ -z "${KUBEARCHIVE_HOST:-}" ]; then
        echo '{"error": "KUBEARCHIVE_HOST environment variable is not set"}' >&2
        exit 1
    fi

    if ! command -v kubectl-ka &> /dev/null; then
        echo '{"error": "kubectl-ka not found. Install via tools/kubectl-ka/install.sh"}' >&2
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo '{"error": "jq not found. Install via tools/jq/install.sh"}' >&2
        exit 1
    fi

    local time_range
    time_range=$(parse_time_spec "$time_spec")
    local start_ts="${time_range% *}"
    local end_ts="${time_range#* }"

    echo "Fetching failed ITS PipelineRuns in $namespace ($start_ts to $end_ts)..." >&2

    local plr_json
    plr_json=$(kubectl ka get pipelineruns -n "$namespace" \
        --kubeconfig "$KUBECONFIG" \
        --host "$KUBEARCHIVE_HOST" \
        -l "pipelines.appstudio.openshift.io/type=test" \
        -o json)

    local result
    result=$(echo "$plr_json" | jq --arg start "$start_ts" --arg end "$end_ts" --arg ns "$namespace" '
        [.items[] |
            select(.metadata.creationTimestamp >= $start and .metadata.creationTimestamp <= $end) |
            select(.status.conditions // [] | map(select(.type == "Succeeded")) | .[0].status == "False") |
            {
                name: .metadata.name,
                namespace: $ns,
                created: .metadata.creationTimestamp,
                application: (.metadata.labels["appstudio.openshift.io/application"] // "N/A"),
                component: (.metadata.labels["appstudio.openshift.io/component"] // "N/A"),
                scenario: (.metadata.labels["test.appstudio.openshift.io/scenario"] // "N/A"),
                optional: (.metadata.labels["test.appstudio.openshift.io/optional"] // "false"),
                event_type: (.metadata.labels["pac.test.appstudio.openshift.io/event-type"] // "N/A"),
                reason: (.status.conditions // [] | map(select(.type == "Succeeded")) | .[0].reason // "Unknown")
            }
        ] | sort_by(.created)
    ')

    local count
    count=$(echo "$result" | jq 'length')
    echo "Found $count failed PipelineRun(s)" >&2

    if [ "$human" = true ]; then
        if [ "$count" -eq 0 ]; then
            echo "No failed ITS PipelineRuns found in the specified time period."
        else
            echo "$result" | jq -r '
                ["NAME", "CREATED", "APPLICATION", "COMPONENT", "SCENARIO", "OPTIONAL", "EVENT", "REASON"],
                (.[] | [.name, .created[:19], .application, .component, .scenario, .optional, .event_type, .reason]) |
                @tsv
            ' | column -t -s$'\t'
        fi
    else
        echo "$result"
    fi
}

main "$@"
