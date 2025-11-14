# Konflux Skill

**Name**: `konflux`

**Description**: Query and manage Konflux/Tekton pipeline resources (pipelinerun, taskrun, pipeline, task) and GitOps resources (release, application, component) using efficient kubectl+jq patterns. Includes RHEL AI release workflow automation and YAML generation tools. Avoids MCP context pollution.

## Contents

- **SKILL.md** - Main skill file with kubectl query patterns and workflows
- **scripts/** - Automation scripts for this skill
  - **generate-release-yaml.sh** - Generate Konflux Release YAML from stage releases

## Skill Overview

This skill provides efficient kubectl+jq query patterns for:

### Tekton Resources
- `pipelinerun` - Pipeline execution instances
- `pipeline` - Pipeline definitions
- `taskrun` - Task execution instances
- `task` - Task definitions

### GitOps/AppStudio Resources
- `release` - Release definitions
- `application` - Application definitions
- `component` - Component definitions

## Key Features

### 1. Query Patterns
- Label selector filtering (server-side)
- jq filtering (client-side)
- Status verification
- Field extraction
- Batch processing

### 2. RHEL AI Release Workflow
Complete workflow for querying stage releases and generating production release YAMLs:
1. Query by commit SHA and component
2. Verify release succeeded
3. Extract release details
4. Generate production release YAML

### 3. Automation Script

**generate-release-yaml.sh** - Automates the release YAML generation process:

```bash
./scripts/generate-release-yaml.sh \
  --component bootc-cuda \
  --sha 239f91eb6a231296b81860443ec0c5580905f7a9 \
  --version 3.0.0 \
  --env prod \
  --rpa bootc-containers \
  --output release.yaml
```

Features:
- Queries Kubernetes for stage release
- Verifies release succeeded
- Extracts snapshot automatically
- Generates properly formatted YAML
- Full validation (SHA length, environment, etc.)

## Usage

### As a Skill

Invoke the skill in Claude Code:
```
/konflux
```

Then ask questions like:
- "Show me failed pipelineruns"
- "List releases for bootc-cuda"
- "Generate a release YAML for bootc-cuda at commit abc123..."

### Direct Script Usage

```bash
# From the skill directory
./scripts/generate-release-yaml.sh --help

# From anywhere
.claude/skills/konflux/scripts/generate-release-yaml.sh [OPTIONS]
```

### In Commands

Reference in slash commands:
```markdown
Use the `/konflux` skill patterns (see "RHEL AI Release Workflow" section)
```

Reference the script:
```bash
.claude/skills/konflux/scripts/generate-release-yaml.sh \
  --component <name> \
  --sha <sha> \
  --version <version> \
  --env <env> \
  --rpa <rpa>
```

## Requirements

- `kubectl` configured and authenticated
- `jq` installed
- Access to Kubernetes cluster with Konflux/Tekton resources

## Used By

- `/rhel-ai-release` command - RHEL AI production release generation
- Other automation workflows requiring Konflux resource queries

## Portability

This skill is self-contained:
- All query patterns in SKILL.md
- Script bundled in same directory
- No external dependencies (except kubectl/jq)
- Can be copied to other projects as-is

## Structure

```
.claude/skills/konflux/
├── README.md                      # This file
├── SKILL.md                       # Main skill with query patterns
└── scripts/                       # Automation scripts
    └── generate-release-yaml.sh   # Release YAML generation script
```
