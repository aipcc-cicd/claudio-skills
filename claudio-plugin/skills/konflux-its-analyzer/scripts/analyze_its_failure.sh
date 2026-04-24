#!/usr/bin/env bash
#
# Analyze Failed ITS PipelineRun
#
# Deep-analyzes a single failed Konflux integration test scenario PipelineRun
# by examining TaskRun statuses and failed task logs via KubeArchive.
#
# Usage:
#   ./analyze_its_failure.sh <namespace> <pipelinerun-name> [OPTIONS]
#
# Environment variables:
#   KUBECONFIG       Path to kubeconfig file (required)
#   KUBEARCHIVE_HOST KubeArchive API server URL (required for log retrieval)
#
# Examples:
#   ./analyze_its_failure.sh ai-tenant rhaiis-test-vllm-podman-neuron-x86-64-pqr7h --human
#   ./analyze_its_failure.sh ai-tenant rhaiis-test-vllm-podman-cuda-x86-64-msrt7

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    cat << 'EOF'
Usage: analyze_its_failure.sh <namespace> <pipelinerun-name> [OPTIONS]

Arguments:
  namespace         Kubernetes namespace
  pipelinerun-name  Name of the PipelineRun to analyze

Options:
  --human               Human-readable output instead of JSON

Environment:
  KUBECONFIG        Path to kubeconfig file (required)
  KUBEARCHIVE_HOST  KubeArchive API server URL (required for log retrieval)
EOF
}

main() {
    local human=false

    if [[ $# -lt 2 ]]; then
        show_usage >&2
        exit 1
    fi

    local namespace="$1"
    local plr_name="$2"
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

    for cmd in kubectl-ka jq; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "{\"error\": \"$cmd not found. Install via tools/$cmd/install.sh\"}" >&2
            exit 1
        fi
    done

    # ── Step 1: Get PipelineRun ──────────────────────────────────────────
    echo "Fetching PipelineRun $plr_name..." >&2

    local plr_json
    plr_json=$(kubectl ka get pipelineruns "$plr_name" -n "$namespace" \
        --kubeconfig "$KUBECONFIG" --host "$KUBEARCHIVE_HOST" -o json)

    local plr_item
    plr_item=$(echo "$plr_json" | jq '.items[0]')

    if [ "$plr_item" = "null" ]; then
        echo "{\"error\": \"PipelineRun $plr_name not found in namespace $namespace\"}" >&2
        exit 1
    fi

    local status
    status=$(echo "$plr_item" | jq -r '.status.conditions // [] | map(select(.type == "Succeeded")) | .[0].status // "Unknown"')

    if [ "$status" != "False" ]; then
        echo "PipelineRun $plr_name is not failed (status: $status)" >&2
        echo "$plr_item" | jq '{pipelinerun: .metadata.name, status: "not failed"}'
        exit 0
    fi

    local summary
    summary=$(echo "$plr_item" | jq -r '.status.conditions // [] | map(select(.type == "Succeeded")) | .[0].message // "Unknown"')

    local metadata
    metadata=$(echo "$plr_item" | jq '{
        event_type: (.metadata.labels["pac.test.appstudio.openshift.io/event-type"] // "N/A"),
        commit_sha: (.metadata.labels["pac.test.appstudio.openshift.io/sha"] // "N/A"),
        application: (.metadata.labels["appstudio.openshift.io/application"] // "N/A"),
        component: (.metadata.labels["appstudio.openshift.io/component"] // "N/A"),
        scenario: (.metadata.labels["test.appstudio.openshift.io/scenario"] // "N/A"),
        optional: (.metadata.labels["test.appstudio.openshift.io/optional"] // "false"),
        repo_url: (.metadata.annotations["pac.test.appstudio.openshift.io/repo-url"] // "N/A"),
        pull_request_number: (.metadata.annotations["build.appstudio.redhat.com/pull_request_number"] // ""),
        log_url: (.metadata.annotations["pac.test.appstudio.openshift.io/log-url"] // "N/A")
    }')

    local event_type repo_url pr_number merge_request_url
    event_type=$(echo "$metadata" | jq -r '.event_type')
    repo_url=$(echo "$metadata" | jq -r '.repo_url')
    pr_number=$(echo "$metadata" | jq -r '.pull_request_number')

    merge_request_url=""
    if [[ ("$event_type" == "Merge_Request" || "$event_type" == "pull_request") && -n "$pr_number" && "$pr_number" != "" ]]; then
        merge_request_url="${repo_url}/-/merge_requests/${pr_number}"
    fi

    echo "PipelineRun status: Failed — $summary" >&2

    # ── Step 2: Get TaskRun statuses ─────────────────────────────────────
    echo "Fetching TaskRuns..." >&2

    local tr_json
    tr_json=$(kubectl ka get taskruns -n "$namespace" \
        --kubeconfig "$KUBECONFIG" \
        --host "$KUBEARCHIVE_HOST" \
        -l "tekton.dev/pipelineRun=$plr_name" \
        -o json)

    local failed_tasks_json
    failed_tasks_json=$(echo "$tr_json" | jq '[
        .items[] |
        select(.status.conditions // [] | map(select(.type == "Succeeded")) | .[0].status == "False") |
        {
            taskrun_name: .metadata.name,
            task: (.metadata.labels["tekton.dev/pipelineTask"] // "unknown"),
            steps: [
                .status.steps[]? |
                select(.terminated.exitCode != 0) |
                {
                    name: .name,
                    exit_code: .terminated.exitCode,
                    reason: (.terminated.reason // "Unknown")
                }
            ]
        }
    ]')

    local failed_count
    failed_count=$(echo "$failed_tasks_json" | jq 'length')
    echo "Found $failed_count failed task(s)" >&2

    # ── Step 3: Get logs of failed TaskRuns ──────────────────────────────
    local analysis_parts=()

    if [ "$failed_count" -gt 0 ]; then
        local i=0
        while [ $i -lt "$failed_count" ]; do
            local taskrun_name task_name
            taskrun_name=$(echo "$failed_tasks_json" | jq -r ".[$i].taskrun_name")
            task_name=$(echo "$failed_tasks_json" | jq -r ".[$i].task")

            local failed_steps
            failed_steps=$(echo "$failed_tasks_json" | jq -r ".[$i].steps[].name")

            if [ -z "$failed_steps" ]; then
                failed_steps="__default__"
            fi

            for step_name in $failed_steps; do
                echo "Fetching logs for task=$task_name step=$step_name..." >&2

                local log_output=""
                if [ "$step_name" = "__default__" ]; then
                    log_output=$(kubectl ka logs "taskrun/$taskrun_name" \
                        -n "$namespace" \
                        --kubeconfig "$KUBECONFIG" \
                        --host "$KUBEARCHIVE_HOST" 2>&1 | tail -1000) || true
                else
                    log_output=$(kubectl ka logs "taskrun/$taskrun_name" \
                        -n "$namespace" \
                        --kubeconfig "$KUBECONFIG" \
                        --host "$KUBEARCHIVE_HOST" \
                        -c "step-$step_name" 2>&1 | tail -1000) || true
                fi

                local step_analysis=""
                if [ -n "$log_output" ] && [ "$log_output" != "unauthorized" ]; then
                    step_analysis="$log_output"
                else
                    step_analysis="Logs unavailable (unauthorized or empty)"
                fi

                analysis_parts+=("[$task_name/$step_name]"$'\n'"$step_analysis")
            done

            i=$((i + 1))
        done
    fi

    local analysis=""
    if [ ${#analysis_parts[@]} -gt 0 ]; then
        analysis=$(printf '%s\n' "${analysis_parts[@]}")
    else
        analysis="No failed tasks found or unable to retrieve logs"
    fi

    # ── Step 4: Build report ─────────────────────────────────────────────
    local failed_tasks_output
    failed_tasks_output=$(echo "$failed_tasks_json" | jq '[.[] | {
        task: .task,
        step: (.steps[0].name // "unknown"),
        exit_code: (.steps[0].exit_code // -1)
    }]')

    local report
    report=$(jq -n \
        --arg plr "$plr_name" \
        --arg ns "$namespace" \
        --arg summary "$summary" \
        --arg analysis "$analysis" \
        --arg mr_url "$merge_request_url" \
        --argjson metadata "$metadata" \
        --argjson failed_tasks "$failed_tasks_output" \
        '{
            pipelinerun: $plr,
            namespace: $ns,
            status: "Failed",
            summary: $summary,
            event_type: $metadata.event_type,
            commit_sha: $metadata.commit_sha,
            application: $metadata.application,
            component: $metadata.component,
            scenario: $metadata.scenario,
            optional: $metadata.optional,
            repo_url: $metadata.repo_url,
            log_url: $metadata.log_url,
            failed_tasks: $failed_tasks,
            analysis: $analysis
        } + (if $mr_url != "" then {merge_request: $mr_url} else {} end)')

    # ── Step 5: Output ─────────────────────────────────────────────────
    if [ "$human" = true ]; then
        print_human_report "$report"
    else
        echo "$report"
    fi
}

print_human_report() {
    local report="$1"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  ITS Failure Analysis Report"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  PipelineRun:  $(echo "$report" | jq -r '.pipelinerun')"
    echo "  Namespace:    $(echo "$report" | jq -r '.namespace')"
    echo "  Application:  $(echo "$report" | jq -r '.application')"
    echo "  Component:    $(echo "$report" | jq -r '.component')"
    echo "  Scenario:     $(echo "$report" | jq -r '.scenario')"
    echo "  Optional:     $(echo "$report" | jq -r '.optional')"
    echo "  Event:        $(echo "$report" | jq -r '.event_type')"
    echo "  Commit:       $(echo "$report" | jq -r '.commit_sha')"

    local mr_url
    mr_url=$(echo "$report" | jq -r '.merge_request // empty')
    if [ -n "$mr_url" ]; then
        echo "  Merge Request: $mr_url"
    fi

    echo "  Log URL:      $(echo "$report" | jq -r '.log_url')"
    echo ""
    echo "  Summary: $(echo "$report" | jq -r '.summary')"
    echo ""
    echo "  Failed Tasks:"
    echo "$report" | jq -r '.failed_tasks[] | "    - \(.task) (step: \(.step), exit code: \(.exit_code))"'
    echo ""
    echo "  Analysis:"
    echo "$report" | jq -r '.analysis' | sed 's/^/    /'
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

main "$@"
