---
name: konflux-its-analyzer
description: Analyze failed Konflux integration test scenario PipelineRuns using KubeArchive. Use when the user asks to analyze failed ITS pipeline runs, debug test failures, or investigate why integration tests failed in Konflux.
allowed-tools: Bash(*/konflux-its-analyzer/scripts/*.sh:*),Bash(*/tools/*/install.sh:*)
compatibility: Requires KUBECONFIG env var pointing to Konflux cluster kubeconfig. Requires KUBEARCHIVE_HOST env var.
---

# Konflux ITS Failure Analyzer

## Overview

Analyze failed Konflux integration test scenario (ITS) PipelineRuns using KubeArchive. Retrieves archived PipelineRuns, identifies failed tasks, fetches logs, and produces root cause analysis reports.

**Namespaces:** If the user does not specify a namespace, use one of:
- `ai-tenant` — RHAIIS components
- `rhel-ai-tenant` — RHEL AI components

**Prerequisites:**
- `kubectl-ka` (KubeArchive CLI) installed and cluster accessible
- `jq` for JSON parsing
- `KUBECONFIG` env var set to kubeconfig file path
- `KUBEARCHIVE_HOST` env var set to KubeArchive API server URL

**Dependency Installation:**
```bash
../../../tools/kubectl-ka/install.sh   # Install kubectl-ka if not present
../../../tools/jq/install.sh           # Install jq if not present
```

## Scripts

### `get_failed_pipelineruns.sh`

Lists failed ITS PipelineRuns within a time period.

**Usage:**
```bash
./scripts/get_failed_pipelineruns.sh <namespace> <time-spec> [--human]
```

**Arguments:**

| Position | Argument | Description |
|----------|----------|-------------|
| 1 | `<namespace>` | Kubernetes namespace |
| 2 | `<time-spec>` | Time period (see formats below) |

**Time specification formats:**

| Format | Example | Description |
|--------|---------|-------------|
| Single date | `2026-04-16` | All failures on that date |
| Date range | `2026-04-14..2026-04-16` | Failures from start to end date |
| Relative hours | `4h` | Last 4 hours |
| Relative days | `2d` | Last 2 days |
| Relative weeks | `1w` | Last week |

**Options:**

| Option | Description |
|--------|-------------|
| `--human` | Table output instead of JSON |

**Examples:**
```bash
./scripts/get_failed_pipelineruns.sh ai-tenant 2026-04-16
./scripts/get_failed_pipelineruns.sh ai-tenant 2026-04-14..2026-04-16 --human
./scripts/get_failed_pipelineruns.sh ai-tenant 4h
```

**Output (JSON):**
```json
[
  {
    "name": "rhaiis-test-vllm-podman-cuda-x86-64-msrt7",
    "namespace": "ai-tenant",
    "created": "2026-04-16T23:49:09Z",
    "application": "rhaiis",
    "component": "rhaiis-cuda-ubi9",
    "scenario": "rhaiis-test-vllm-podman-cuda-x86-64",
    "optional": "true",
    "event_type": "Merge Request",
    "reason": "Failed"
  }
]
```

---

### `analyze_its_failure.sh`

Deep-analyzes a single failed PipelineRun. Examines TaskRun statuses, fetches failed task logs, and produces a root cause analysis.

**Usage:**
```bash
./scripts/analyze_its_failure.sh <namespace> <pipelinerun-name> [OPTIONS]
```

**Arguments:**

| Position | Argument | Description |
|----------|----------|-------------|
| 1 | `<namespace>` | Kubernetes namespace |
| 2 | `<pipelinerun-name>` | Name of the failed PipelineRun |

**Options:**

| Option | Description |
|--------|-------------|
| `--human` | Human-readable output instead of JSON |

**Examples:**
```bash
./scripts/analyze_its_failure.sh ai-tenant rhaiis-test-vllm-podman-neuron-x86-64-pqr7h --human
./scripts/analyze_its_failure.sh ai-tenant rhaiis-test-vllm-podman-cuda-x86-64-msrt7
```

**Output (JSON):**
```json
{
  "pipelinerun": "rhaiis-test-vllm-podman-neuron-x86-64-pqr7h",
  "namespace": "ai-tenant",
  "status": "Failed",
  "summary": "Tasks Completed: 7 (Failed: 1, Cancelled 0), Skipped: 6",
  "event_type": "Merge Request",
  "commit_sha": "abc123...",
  "application": "rhaiis",
  "component": "rhaiis-neuron-ubi9",
  "scenario": "rhaiis-test-vllm-podman-neuron-x86-64",
  "optional": "true",
  "repo_url": "https://gitlab.com/redhat/rhel-ai/rhaiis/containers",
  "merge_request": "https://gitlab.com/redhat/rhel-ai/rhaiis/containers/-/merge_requests/351",
  "log_url": "https://konflux-ui.apps.../pipelinerun/...",
  "failed_tasks": [
    {
      "task": "test-inference",
      "step": "unnamed-0",
      "exit_code": 1
    }
  ],
  "analysis": "Human-readable root cause summary"
}
```

## Common Workflows

### Workflow 1: Find and Analyze Failures for a Date

```bash
# Step 1: List failed PipelineRuns
./scripts/get_failed_pipelineruns.sh ai-tenant 2026-04-16 --human

# Step 2: Analyze a specific failure
./scripts/analyze_its_failure.sh ai-tenant rhaiis-test-vllm-podman-cuda-x86-64-msrt7 --human
```

### Workflow 2: Recent Failures

```bash
# Check last 4 hours
./scripts/get_failed_pipelineruns.sh ai-tenant 4h --human

# Check last week
./scripts/get_failed_pipelineruns.sh ai-tenant 1w
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| PipelineRun not found | Exit 1 with error JSON |
| PipelineRun not failed | Exit 0 with status info |
| KUBECONFIG not set | Exit 1 with error |
| KUBEARCHIVE_HOST not set | Exit 1 with error |
| kubectl-ka not installed | Exit 1 with install hint |
| Logs unauthorized | Analysis notes "Logs unavailable" |
| No failed tasks found | Analysis notes "No failed tasks" |

## Dependencies

**Required:** `kubectl-ka`, `jq` — installed via `tools/*/install.sh`
