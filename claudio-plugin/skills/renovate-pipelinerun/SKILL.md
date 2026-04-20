---
name: renovate-pipelinerun
description: Trigger and monitor Renovate PipelineRuns on OpenShift. Use this skill when the user asks to run Renovate, start a Renovate pipeline, check Renovate run status, view Renovate logs, or list available Renovate pipelines. Wraps tkn and kubectl CLI commands for Tekton PipelineRun management.
allowed-tools: Bash(*/renovate-pipelinerun/scripts/*.sh:*),Bash(*/tools/*/install.sh:*)
---

# Renovate PipelineRun

## Overview

Trigger and monitor self-hosted Renovate PipelineRuns on OpenShift via Tekton. This skill automates cluster authentication validation, pipeline discovery, busy-checking, PipelineRun creation, status monitoring, and log retrieval.

**Prerequisites:**
- `kubectl` installed (auto-installed via `tools/kubectl/install.sh`) and authenticated to the cluster
- `tkn` command available (auto-installed via `tools/tkn/install.sh`)
- `RENOVATE_NAMESPACE` environment variable (defaults to `rhel-ai-cicd--renovate-runner`)

## Example Usage

List available pipelines:
> /renovate-pipelinerun list available Renovate pipelines

Start a pipeline (dry-run — no actual execution):
> /renovate-pipelinerun dry-run start of renovate-rhelai-core

Start a pipeline for real:
> /renovate-pipelinerun start renovate-rhelai-core

Start even if busy:
> /renovate-pipelinerun force start renovate-rhelai-core

Check status of a pipeline (shows most recent run):
> /renovate-pipelinerun what's the status of renovate-rhelai-core?

Check status of a specific PipelineRun:
> /renovate-pipelinerun status of renovate-rhelai-core-run-abc123

Show recent runs across all pipelines:
> /renovate-pipelinerun show recent Renovate activity

Show last 5 runs for a pipeline:
> /renovate-pipelinerun show last 5 runs of renovate-rhelai-wheels

View logs from a PipelineRun:
> /renovate-pipelinerun show logs for renovate-rhelai-core-run-abc123

View last 50 lines of logs:
> /renovate-pipelinerun show last 50 lines of logs for renovate-rhelai-core-run-abc123

## Scripts

All scripts are in the `scripts/` directory and must be invoked with their full absolute path.

### check_auth.sh

Validate cluster authentication and namespace configuration.

```bash
/full/path/to/renovate-pipelinerun/scripts/check_auth.sh
```

Checks:
- `kubectl` is installed and user is authenticated
- `RENOVATE_NAMESPACE` namespace exists on the cluster

### list_pipelines.sh

List available Renovate pipelines in the configured namespace.

```bash
/full/path/to/renovate-pipelinerun/scripts/list_pipelines.sh
```

Output: JSON array of pipelines with name and creation timestamp, filtered to the `renovate-` prefix.

### start_pipeline.sh

Start a PipelineRun for a specified Renovate pipeline.

```bash
/full/path/to/renovate-pipelinerun/scripts/start_pipeline.sh <pipeline-name> [--force] [--dry-run]
```

Arguments:
- `pipeline-name` — Name of the pipeline (e.g., `renovate-rhelai-core`)
- `--force` — Start even if the pipeline is currently busy (skip busy-check warning)
- `--dry-run` — Output the PipelineRun YAML without creating it

Behavior:
- Validates auth and namespace
- Checks if the pipeline exists
- Checks if the pipeline is busy (has active TaskRuns)
- If busy, reports the active PipelineRun and exits with code 2 (use `--force` to override)
- Starts the PipelineRun with: `--serviceaccount renovate-admin`, `--pipeline-timeout 2h`, `-w name=shared-workspace,emptyDir=""`, `--use-param-defaults`
- Reports the created PipelineRun name

### get_status.sh

Get the status of a PipelineRun or the most recent run for a pipeline.

```bash
/full/path/to/renovate-pipelinerun/scripts/get_status.sh <name> [--history N]
/full/path/to/renovate-pipelinerun/scripts/get_status.sh --all [--history N]
```

Arguments:
- `name` — A PipelineRun name or pipeline name (auto-detects which)
- `--history N` — List the last N PipelineRuns instead of showing details (default: 10)
- `--all` — Show runs across all `renovate-` pipelines

Output: JSON with PipelineRun details including status, start time, duration, and TaskRun summary.

### get_logs.sh

Retrieve logs from a PipelineRun or TaskRun.

```bash
/full/path/to/renovate-pipelinerun/scripts/get_logs.sh <name> [--lines N]
```

Arguments:
- `name` — A PipelineRun name or TaskRun name
- `--lines N` — Number of log lines to retrieve (default: 200)

## Script Execution Requirements

1. **Single-line commands only** — NO line breaks or backslash continuations
2. **DO NOT change directory** — execute scripts using their full absolute path
3. **Full path required** — the script must be invoked with its full filesystem path
