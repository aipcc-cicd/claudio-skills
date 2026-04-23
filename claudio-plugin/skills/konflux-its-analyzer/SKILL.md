---
name: konflux-its-analyzer
description: Analyze failed Konflux integration test scenario PipelineRuns using KubeArchive. Use when the user asks to analyze failed ITS pipeline runs, debug test failures, or investigate why integration tests failed in Konflux.
allowed-tools: Bash(*/konflux-its-analyzer/scripts/*.sh:*),Bash(*/tools/*/install.sh:*),Bash(*/slack-utilities/scripts/slack/*.py:*)
compatibility: Requires KUBECONFIG env var pointing to Konflux cluster kubeconfig. Requires KUBEARCHIVE_HOST env var. Requires SLACK_XOXC_TOKEN and SLACK_XOXD_TOKEN for Slack posting.
---

# Konflux ITS Failure Analyzer

## Overview

Analyze failed Konflux integration test scenario (ITS) PipelineRuns using KubeArchive. Retrieves archived PipelineRuns, identifies failed tasks, fetches logs, and produces root cause analysis reports. Optionally posts reports to Slack.

**Namespaces:** If the user does not specify a namespace, use one of:
- `ai-tenant` — RHAIIS components
- `rhel-ai-tenant` — RHEL AI components

**Prerequisites:**
- `kubectl-ka` (KubeArchive CLI) installed and cluster accessible
- `jq` for JSON parsing
- `KUBECONFIG` env var set to kubeconfig file path
- `KUBEARCHIVE_HOST` env var set to KubeArchive API server URL
- For Slack: `SLACK_XOXC_TOKEN` and `SLACK_XOXD_TOKEN` env vars

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

Deep-analyzes a single failed PipelineRun. Examines TaskRun statuses, fetches failed task logs, and produces a root cause analysis. Optionally posts a report to Slack.

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

## Slack Reporting

When the user asks to post results to Slack, follow this workflow:

1. **Resolve channel name to ID** using the slack-utilities `find_channel.py` script:
   ```bash
   ../../slack-utilities/scripts/slack/find_channel.py my-channel
   # Returns: {"id": "C04ABCD1234", "name": "my-channel", ...}
   ```

2. **Run `analyze_its_failure.sh`** to get JSON output:
   ```bash
   ./scripts/analyze_its_failure.sh ai-tenant <pipelinerun-name>
   ```

3. **Analyze the JSON output** — read the `analysis` field and `failed_tasks` to understand the root cause. Write a brief, human-readable explanation of why the test failed and what could fix it.

4. **Post to Slack via `post_message.py`** using this message template (use actual newlines, not literal `\n`):
   ```
   :red_circle: Optional/Required Konflux integration test failure: <log_url|pipelinerun_name> for merge request <mr_url|!number>
   ```<key error lines from analysis field>```
   Root cause: <your human-readable analysis — what failed, why, and whether it's a code issue or infra/flaky test>
   ```
   The root cause section should be concise (2-4 sentences) and actionable — tell the reader what broke and whether they need to act on it.

## Common Workflows

### Workflow 1: Find and Analyze Failures for a Date

```bash
# Step 1: List failed PipelineRuns
./scripts/get_failed_pipelineruns.sh ai-tenant 2026-04-16 --human

# Step 2: Analyze a specific failure
./scripts/analyze_its_failure.sh ai-tenant rhaiis-test-vllm-podman-cuda-x86-64-msrt7 --human
```

### Workflow 2: Analyze and Report to Slack

```bash
# Step 1: Get analysis JSON
./scripts/analyze_its_failure.sh ai-tenant rhaiis-test-vllm-podman-cuda-x86-64-msrt7

# Step 2: Compose message with human-readable root cause and post to Slack
../../slack-utilities/scripts/slack/post_message.py C0123ABCDEF "<message>"
```

### Workflow 3: Recent Failures

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

**For Slack posting:** Uses slack-utilities skill (`post_message.py`, `find_channel.py`). Requires `SLACK_XOXC_TOKEN` and `SLACK_XOXD_TOKEN` env vars.
