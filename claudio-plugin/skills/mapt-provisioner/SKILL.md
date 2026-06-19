---
name: mapt-provisioner
description: Provision and manage cloud machines and services using mapt. Use this skill when the user asks to create, destroy, or check the status of cloud VMs, RHELAI instances, OpenShift clusters (SNC), or any infrastructure that mapt supports. Covers AWS and Azure providers. Handles spot instances, GPU-enabled workloads, and OpenShift profiles.
compatibility: Requires MAPT_BACKEND_URL. AWS targets need AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (or AWS_PROFILE) and AWS_DEFAULT_REGION. Azure targets need ARM_TENANT_ID, ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, and ARM_CLIENT_SECRET (mapt maps these to AZURE_* internally); azblob backend also needs AZURE_STORAGE_ACCOUNT and AZURE_STORAGE_KEY. SNC targets also need PULL_SECRET_FILE.
allowed-tools: Bash(*/mapt-provisioner/scripts/*.sh:*),Bash(*/tools/mapt/install.sh:*),Bash(mapt * --help),Bash(ssh -i /tmp/mapt-conn-details/* *)
---

# Mapt Provisioner

Provision and manage cloud machines and services using [mapt](https://github.com/redhat-developer/mapt).

## Interpreting Natural Language Requests

Users will ask in natural language — extract the intent and map it to script flags. Do not require a specific incantation.

| User says | Maps to |
|-----------|---------|
| "RHEL AI" / "RHELAI" / "rhel-ai" | `provision_rhelai.sh` |
| "OpenShift" / "SNC" / "single-node" | `provision_snc.sh` |
| "on AWS" / "in AWS" / "using AWS" | `--provider aws` |
| "on Azure" / "in Azure" | `--provider azure` |
| "spot" / "spot instance" / "using spot" | `--spot` |
| "tag it X=Y" / "tags X=Y,A=B" | `--tags X=Y,A=B` |
| "store state in s3://..." / "backend s3://..." | set `MAPT_BACKEND_URL=s3://...` |
| "destroy it" / "tear it down" / "clean up" | `destroy.sh` |
| "what versions are available?" / "list images" | `mapt <aws\|azure> rhel-ai list-versions --accelerator <acc>` |
| "check status" / "is it up?" | `check_status.sh` |
| "connect to it" / "SSH in" / "run X on it" | SSH directly using conn-details |

**Version normalization:** Users often omit the patch version or use spaces/wrong separators. Normalize before passing `--version`:
| User says | Normalized |
|-----------|------------|
| "3.4 ea1" / "3.4-ea1" / "3.4 ea.1" | `3.4.0-ea.1` |
| "3.4 ea2" / "3.4-ea2" | `3.4.0-ea.2` |
| "3.4" / "3.4.0" | `3.4.0` |
| "3.3.1" | `3.3.1` (already correct) |

The pattern is `MAJOR.MINOR.PATCH` with optional `-ea.N` suffix. If the user omits `.PATCH`, assume `.0`. If they write `ea` without a dot before the number, add it.

**Env var defaults:** `AWS_DEFAULT_REGION` and credentials should be pre-configured in the environment — do not ask the user to provide them in their request. If `MAPT_BACKEND_URL` is already set in the environment, the user does not need to mention it either.

## Rules

- **DO NOT provision without `MAPT_BACKEND_URL` set.** Without a persistent state backend, provisioned resources become orphaned — VMs, GPUs, and networking bill indefinitely with no way to destroy them through mapt. The scripts enforce this, but do not attempt to bypass it.
- **DO NOT destroy without confirming the project name and target with the user.** Echo back the project name, provider, and target type. Wait for explicit confirmation before running destroy.
- **DO NOT use `--force-destroy` without user confirmation.** Only use when the user confirms a Pulumi lock is stale.
- **DO NOT provision GPU instances without confirming cost implications.** GPU instances are significantly more expensive than standard instances.
- **Always remind the user about ongoing charges** after provisioning. Provide the project name and the exact destroy command they'll need later.

## Provisioning Workflow

### Step 1: Pre-Flight

Before running any provisioning script, verify the required environment variables are set:

| Target | Required Variables |
|--------|--------------------|
| All | `MAPT_BACKEND_URL` (s3://... or azblob://...) |
| AWS | `AWS_DEFAULT_REGION` (e.g. `us-east-1`) — needed for AWS SDK initialization; should be pre-configured in the environment, not extracted from the user's request. mapt still picks the cheapest spot region globally regardless of this value. |
| AWS | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`, or `AWS_PROFILE` |
| Azure | `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET` (mapt maps these to `AZURE_*` internally via `setAZIdentityEnvs()`) |
| Azure (azblob backend) | `AZURE_STORAGE_ACCOUNT`, `AZURE_STORAGE_KEY` |
| SNC (additionally) | `PULL_SECRET_FILE` (path to file from https://console.redhat.com/openshift/create/local) |

If `MAPT_BACKEND_URL` is not set, **stop and explain the orphaned-resource risk**. Do NOT proceed.

If your Pulumi state was encrypted with a non-default passphrase, export `PULUMI_CONFIG_PASSPHRASE=<your-passphrase>` before running. The scripts default to `passphrase`, which matches the mapt container configuration.

OpenShift SNC is AWS only — mapt does not support Azure for SNC.

### Step 2: Provision

**RHELAI:**
```bash
/full/path/to/scripts/provision_rhelai.sh --provider <aws|azure> [options]
```

| Option | Purpose |
|--------|---------|
| `--version` | RHELAI version (auto-discovered if omitted; specify manually if discovery fails) |
| `--cpus`, `--memory` | Instance size |
| `--gpus` | Number of GPUs |
| `--accelerator` | GPU type: `cuda` or `rocm` (mapt default: cuda) |
| `--spot` | Use spot instances (cheaper, can be interrupted) |
| `--spot-eviction-tolerance` | Spot tolerance: `lowest`, `low`, `medium`, `high`, `highest`. Defaults to `highest` when `--spot` is used (GPU workloads are typically testing, not production). Override with a lower value only if the user explicitly needs long-running stability. |
| `--tags` | Cost attribution: `team=myteam,env=dev` |
| `--project-name` | Stack identifier (default: auto-generated) |

**OpenShift SNC:**
```bash
/full/path/to/scripts/provision_snc.sh [options]
```

| Option | Purpose |
|--------|---------|
| `--version` | OpenShift version (default: 4.21.0) |
| `--profile` | Comma-separated: `virtualization`, `serverless`, `serverless-serving`, `serverless-eventing`, `servicemesh`, `ai`, `nvidia` |
| `--arch` | `x86_64` or `arm64` (mapt default: x86_64) |
| `--spot` | Use spot instances |
| `--tags` | Cost attribution |
| `--pull-secret-file` | Overrides `PULL_SECRET_FILE` env var |
| `--project-name` | Stack identifier (default: auto-generated) |

The `ai` profile automatically includes `servicemesh` and `serverless-serving` and raises minimum instance size to 16 vCPUs.

### Handling Failures — Hard Stop Rules

These are **blocking rules**. Each one requires a full stop and explicit user confirmation before taking any further action — including cleanup, retries, or waiting.

**STOP immediately and ask the user when:**
- Auto-discovered version contains `-ea` — do not run the provision script. Show the EA version and ask whether to proceed, use a different accelerator, or specify a version manually.
- Provisioning fails for any reason — do not retry with different parameters. Report the exact error and offer options. Wait for the user to choose one.
- A destroy step fails — keep going until it succeeds. Monitor the output, detect transient errors (e.g. Azure NIC reservation, lock conflicts), wait the duration indicated in the error, and retry automatically. Tell the user what you're waiting for. Only stop and report if a non-transient error occurs (e.g. credentials expired, stack not found).
- Any step produces a partial resource state — do not chain follow-up actions. Report what was created and what failed, then stop.

**Never:**
- Retry autonomously with different flags (`--version`, `--spot`, `--accelerator`, etc.)
- Schedule a delayed retry (e.g. `sleep 180 && destroy`) without explicit user instruction
- Chain a retry onto a destroy without the user confirming both steps separately

### Step 3: Verify and Report

After provisioning completes:

1. Run `check_status.sh` to confirm the stack exists:
```bash
/full/path/to/scripts/check_status.sh --project-name <project-name>
```
2. Show the user: connection details, project name, and the destroy command for later.

## Destroy Workflow

### Step 1: Confirm with User

Before destroying, echo back and get explicit confirmation:
- Project name
- Provider (aws or azure)
- Target type (rhel-ai, openshift-snc, rhel, fedora, mac, windows, kind, eks, aks, ubuntu)

### Step 2: Destroy

```bash
/full/path/to/scripts/destroy.sh --provider <provider> --target <target> --project-name <name>
```

If destroy fails with a Pulumi lock error: explain that a stale lock is blocking (common in container environments), ask if the user wants to force it, and only then retry with `--force-destroy`.

### Step 3: Verify

Run `check_status.sh` to confirm the stack is gone.

## Connect to a Provisioned Machine

After provisioning, connection details are written to `/tmp/mapt-conn-details/<project-name>/`. The SSH key lives there — use SSH directly rather than printing the command for the user to run.

When the user asks to connect or run something on the machine, **always show the exact SSH command first and wait for confirmation** before executing. This is a live VM with real cloud costs — never run commands autonomously without the user knowing what will execute.

```bash
ssh -i /tmp/mapt-conn-details/<project-name>/id_rsa \
    -o StrictHostKeyChecking=no \
    cloud-user@<host> "<command>"
```

For read-only checks (e.g. `hostname`, `uname -r`, `systemctl status`) you may execute immediately after showing the command. For anything that modifies system state, explicitly wait for the user to confirm.

The host is the ELB DNS name shown in the provisioning output. If connection details are missing, run `check_status.sh` — it will display them if they exist locally, or retrieve the project name from Pulumi state.

## Check Status

```bash
/full/path/to/scripts/check_status.sh --project-name <project-name>
```

Queries the Pulumi state backend directly (mapt has no native status command) and displays connection details if available locally.

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| Missing credentials | Env vars not set | Tell user which specific variables to set for their provider |
| `MAPT_BACKEND_URL` not set | No state backend | **Stop.** Explain orphaned-resource risk. Do not proceed. |
| Backend unreachable | S3 bucket or Azure blob doesn't exist or no access | Verify URL and credentials. If state is lost, resources must be cleaned up manually via cloud console. |
| Quota exceeded | Cloud provider capacity limits | Try different instance size, try `--spot`, or increase quotas with provider |
| Pulumi lock stale | Previous session died without releasing lock | Use `--force-destroy` after user confirmation |
| Spot eviction | Cloud provider reclaimed the instance | Re-provision. Recommend without `--spot` for long-running workloads. |
| Provisioning hangs | Cloud provider issue or resource unavailability | Check cloud console for partial resources. Project name + backend URL help locate Pulumi state for manual cleanup. |

## Installation

mapt is installed automatically when any script is run (via `_common.sh`). You do not need to install it manually. If a script fails with a mapt-related error unrelated to installation, check the error message directly.
