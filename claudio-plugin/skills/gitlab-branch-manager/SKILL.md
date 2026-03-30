---
name: gitlab-branch-manager
description: Create and protect GitLab branches. Use when the user asks to create a branch, protect a branch, or set up branch protection rules on GitLab. Uses the glab GitLab CLI. The script takes three required positional args in order: repo, branch-name, ref (no --ref flag).
allowed-tools: Bash(*/gitlab-branch-manager/scripts/*.sh:*),Bash(*/tools/glab/install.sh:*),Bash(*/tools/jq/install.sh:*)
---

# GitLab Branch Manager

## Overview

Create GitLab branches and apply protection rules. Designed for release workflows but usable for any branch management scenario.

**Prerequisites:**
- `glab` command is available and authenticated
- Works with gitlab.com, GitLab Self-Managed, and GitLab Dedicated
- `jq` for JSON parsing

**Installation:**
```bash
# glab CLI (required)
../../../tools/glab/install.sh

# jq (required)
../../../tools/jq/install.sh
```

## Core Concepts

- **Protected Branch**: A branch with restrictions on who can push, merge, force-push, and unprotect
- **Access Levels**: `0` = No access, `30` = Developer, `40` = Maintainer, `60` = Admin (self-managed only)

## Default Protection Rules

| Rule | Default | Effect |
|------|---------|--------|
| `push_access_level` | `0` (No access) | Direct push blocked for everyone |
| `merge_access_level` | `40` (Maintainer) | Only maintainers can merge MRs |
| `allow_force_push` | `false` | Force push blocked |
| `code_owner_approval_required` | `false` | No code owner approval required |

All rules are configurable via flags. Defaults enforce a strict protection posture suitable for release branches, matching the pattern used in production repositories.

Note: `unprotect_access_level` is not set by default (uses GitLab server default). Use `--unprotect-level` or `--rule unprotect_access_level=40` to set it explicitly.

Note: `push_access_level=0` already blocks direct push and deletion for everyone.

## Repo Input Format

The script accepts three input formats:

| Format | Example | Resolution |
|--------|---------|------------|
| Short name | `my-project` | Resolved via GitLab API search |
| Full path | `my-org/my-group/my-project` | Used as-is |
| URL | `https://gitlab.com/my-org/my-group/my-project.git` | Parsed to extract project path |

## Script Reference

### `create_and_protect_branch.sh`

Creates a branch and applies protection rules in a single operation.

**Usage:**
```bash
./scripts/create_and_protect_branch.sh <repo> <branch-name> <ref> [OPTIONS]
```

IMPORTANT: All three positional arguments are required and must appear in this exact order. There is no `--ref` flag — the ref is always the third positional argument.

**Positional arguments (required, in order):**

| Position | Argument | Description |
|----------|----------|-------------|
| 1 | `<repo>` | Repo name, full path, or URL |
| 2 | `<branch-name>` | Name for the new branch |
| 3 | `<ref>` | Source ref to branch from (tag, commit SHA, or branch name) |

**Options (all optional):**

| Option | Default | Description |
|--------|---------|-------------|
| `--push-level N` | `0` | Push access level |
| `--merge-level N` | `40` | Merge access level |
| `--unprotect-level N` | not set | Unprotect access level |
| `--allow-force-push` | `false` | Allow force push |
| `--code-owner-approval` | `false` | Require code owner approval |
| `--gitlab-host HOST` | `gitlab.com` | GitLab hostname |
| `--rule KEY=VALUE` | -- | Override any protection rule by key |
| `--dry-run` | -- | Show planned actions, no API calls |
| `--human-readable` | -- | Human-readable output |

**Examples:**
```bash
# Create and protect a release branch from a tag
./scripts/create_and_protect_branch.sh my-project release-1.5 v1.4.0

# Branch from main
./scripts/create_and_protect_branch.sh my-org/my-group/my-project release-1.5 main

# Custom protection levels
./scripts/create_and_protect_branch.sh my-project release-1.5 v1.4.0 --push-level 40 --merge-level 40

# Override any rule with --rule
./scripts/create_and_protect_branch.sh my-project release-1.5 v1.4.0 --rule merge_access_level=30

# Dry run - see what would happen
./scripts/create_and_protect_branch.sh my-project release-1.5 v1.4.0 --dry-run

# From a URL
./scripts/create_and_protect_branch.sh https://gitlab.com/my-org/my-group/my-project.git release-1.5 v1.4.0
```

**Output (JSON, default):**
```json
{
  "repository": "my-org/my-group/my-project",
  "branch": "release-1.5",
  "ref": "main",
  "branch_created": true,
  "protection_applied": true,
  "protection_rules": {
    "push_access_level": 0,
    "merge_access_level": 40,
    "allow_force_push": false,
    "code_owner_approval_required": false
  }
}
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Branch already exists | Exit 1 with error JSON |
| Protection matches requested rules | Exit 0, info logged to stderr |
| Protection differs from requested | Exit 1 with error JSON showing current vs requested rules |
| Source ref not found | Exit 1 with error JSON |
| Insufficient permissions | Exit 1 with error JSON |
| Short name matches multiple projects | Exit 1 with error JSON listing candidates |

## Dependencies

**Required:** `glab` (install via `tools/glab/install.sh`), `jq` (install via `tools/jq/install.sh`)
