# Claudio Skills Plugin

## Overview

This repository contains **Claudio Skills Plugin** - a Claude Code plugin that extends Claude with specialized skills for DevOps and cloud-native development workflows. The plugin provides skills designed to streamline interactions with GitLab, Konflux, and AWS CloudWatch Logs.

## What is this for?

This plugin enables Claude Code to:

- **Analyze GitLab CI/CD job failures** using structured scripts for pipeline debugging
- **Orchestrate Konflux production releases** with self-contained stage-to-production workflows
- **Troubleshoot and analyze AWS CloudWatch Logs** for application debugging and monitoring
- **Create and protect GitLab branches** for release workflows and branch management

These skills allow you to leverage Claude as an intelligent assistant for complex DevOps tasks, from querying merge requests to deploying production releases and troubleshooting application issues across multiple components.

## Plugin Structure

```
claudio-plugin/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata
├── tools/
│   ├── common.sh                # Shared library for tool installers
│   ├── TOOLS.md                 # Tool installation guide
│   ├── aws-cli/
│   │   └── install.sh           # AWS CLI installer
│   ├── jq/
│   │   └── install.sh           # jq installer
│   ├── kubectl/
│   │   └── install.sh           # kubectl installer
│   ├── glab/
│   │   └── install.sh           # glab GitLab CLI installer
│   ├── skopeo/
│   │   └── install.sh           # skopeo installer
│   └── python/
│       ├── install.sh           # Python pip installer
│       ├── konflux-release-requirements.txt  # PyYAML
│       └── slack-requirements.txt            # requests
└── skills/
    ├── gitlab-job-analyzer/
    │   ├── SKILL.md             # GitLab CI/CD job analysis skill
    │   └── scripts/
    │       ├── analyze_recent_jobs.sh   # Recent job summary
    │       ├── analyze_by_runner.sh     # Runner-specific analysis
    │       ├── analyze_pipeline.sh      # Single pipeline deep dive
    │       ├── compare_job_logs.sh      # Compare job runs
    │       ├── analyze_dependencies.sh  # Dependency graph analysis
    │       └── extract_errors.sh        # Error categorization
    ├── konflux-release/
    │   ├── SKILL.md             # Konflux release workflow skill
    │   └── scripts/
    │       └── generate_release_yaml.py  # Release YAML generator
    ├── aws-log-analyzer/
    │   ├── SKILL.md             # AWS CloudWatch Logs troubleshooting skill
    │   └── scripts/
    │       ├── analyze_errors.sh        # Error analysis
    │       ├── find_recent_errors.sh    # Recent error search
    │       ├── run_insights_query.sh    # Custom Insights queries
    │       ├── trace_request.sh         # Cross-service request tracing
    │       └── tail_logs.sh             # Real-time log monitoring
    └── gitlab-branch-manager/
        ├── SKILL.md             # GitLab branch creation and protection skill
        └── scripts/
            └── create_and_protect_branch.sh  # Branch creation + protection
```

## Tools Management

The `claudio-plugin/tools/` directory contains centralized installation scripts for CLI tools used by skills. This system provides a consistent, maintainable way to manage tool dependencies across all skills.

### Philosophy

**Design Principles:**
- **Simplicity:** Scripts do one thing well - install the tool if not present
- **Reusability:** Common functions are shared via `common.sh` library
- **Linux-only:** Focus on Linux x86_64 and ARM64 (aarch64) architectures
- **Minimal options:** Only `--check` flag for verification
- **Idempotent:** Safe to run multiple times

### Directory Structure

```
claudio-plugin/tools/
├── common.sh              # Shared library with common functions
├── TOOLS.md              # Comprehensive guide for adding new tools
├── <tool-name>/
│   └── install.sh        # Installation script for the tool
└── ...
```

### Common Library (`common.sh`)

The `common.sh` library provides shared functions used across all tool installation scripts:

**Available Functions:**
- `log()` - Simple logging to stdout
- `detect_arch()` - Detect architecture (x86_64 or aarch64)
- `verify_linux()` - Verify running on Linux
- `command_exists()` - Check if command exists in PATH
- `version_gte()` - Semantic version comparison
- `is_in_path()` - Check if directory is in PATH
- `warn_if_not_in_path()` - Warn if install directory not in PATH

**Usage in scripts:**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"
```

### Currently Available Tools

**AWS CLI** (`tools/aws-cli/install.sh`)
- Installs AWS CLI v2
- Used by: aws-log-analyzer skill
- Supports: Linux x86_64, ARM64

**glab** (`tools/glab/install.sh`)
- Installs glab GitLab CLI
- Used by: gitlab, gitlab-job-analyzer, konflux-release skills
- Supports: Linux x86_64, ARM64

**jq** (`tools/jq/install.sh`)
- Installs jq JSON processor
- Used by: Multiple skills for JSON parsing
- Supports: Linux x86_64, ARM64

**kubectl** (`tools/kubectl/install.sh`)
- Installs kubectl Kubernetes CLI
- Used by: konflux-release skill
- Supports: Linux x86_64, ARM64

**skopeo** (`tools/skopeo/install.sh`)
- Installs skopeo via system package manager (dnf/apt/apk)
- Used by: konflux-release skill
- Supports: Linux (RHEL, Fedora, Ubuntu, Debian, Alpine)

### Adding New Tools

**When a skill requires a new CLI tool, follow this process:**

1. **Check if the tool already exists** in `claudio-plugin/tools/`

2. **Read the comprehensive guide:** `claudio-plugin/tools/TOOLS.md`
   - Contains complete template
   - Installation patterns (binary, archive, package manager)
   - Common pitfalls and best practices
   - Testing checklist

3. **Create the tool directory:**
   ```bash
   mkdir -p claudio-plugin/tools/<tool-name>
   ```

4. **Use the template** from `TOOLS.md` and customize:
   - Replace placeholders with tool-specific details
   - Add Renovate version tracking
   - Implement version detection
   - Add download URLs for x86_64 and ARM64
   - Choose appropriate installation pattern

5. **Key Guidelines:**
   - ✓ **Use `common.sh` functions** - Always check for existing functions first
   - ✓ **Linux x86_64 and ARM64 only** - No macOS, Windows, or other architectures
   - ✓ **Minimal options** - Only support `--check` flag
   - ✓ **Version tracking** - Use Renovate comments for automatic updates
   - ✓ **Idempotent** - Safe to run multiple times
   - ✗ **Don't add** `--help`, `--version`, or `--force` flags
   - ✗ **Don't duplicate** functions from `common.sh`

6. **Test the script:**
   ```bash
   # Check syntax
   bash -n tools/<tool>/install.sh

   # Test installation
   tools/<tool>/install.sh

   # Test idempotency
   tools/<tool>/install.sh
   ```

7. **Update skill documentation** to reference the new tool

8. **Update skill's `check_deps.sh`** if the skill uses one

### Script Template Summary

Each tool installer follows this structure:

```bash
#!/usr/bin/env bash
# Header with usage

set -euo pipefail

# Load common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Version tracking for Renovate
# renovate: datasource=github-releases depName=org/repo
TOOL_VERSION="x.y.z"

# Configuration (install directory detection)

# get_tool_version() - Extract version from tool
# check_tool() - Verify installation and version
# install_tool() - Download and install for detected architecture

# main() - Parse --check flag, install if needed
```

### Example: Using Tool Installers

**From a skill's dependency checker:**
```bash
# skills/my-skill/scripts/check_deps.sh

AWS_CLI_INSTALL_SCRIPT="$TOOLS_DIR/aws-cli/install.sh"

# Check if installed
"$AWS_CLI_INSTALL_SCRIPT" --check

# Install if needed
"$AWS_CLI_INSTALL_SCRIPT"
```

**Direct usage:**
```bash
# Check if AWS CLI is installed
claudio-plugin/tools/aws-cli/install.sh --check

# Install AWS CLI if needed
claudio-plugin/tools/aws-cli/install.sh
```

### Version Management with Renovate

All tool installers use Renovate for automatic version updates:

```bash
# renovate: datasource=github-releases depName=aws/aws-cli
AWS_CLI_VERSION="2.15.17"
```

When a new version is released, Renovate automatically creates a PR to update the version.

### For Complete Documentation

**See `claudio-plugin/tools/TOOLS.md` for:**
- Complete script template with all sections
- Detailed function documentation
- 3 installation patterns (binary, archive, package manager)
- Common pitfalls with examples
- Step-by-step walkthrough for adding a new tool
- Testing checklist
- Maintenance guidelines

**This is the authoritative guide for all tool installation scripts.**

## Skills Included

### 1. GitLab Job Analyzer Skill

**Purpose:** Analyze GitLab CI/CD job failures, parse logs, and identify error patterns.

**Use cases:**
- Summarize job activity across pipelines in a time range
- Analyze failures by runner type
- Deep-dive into specific pipeline failures
- Compare successful vs failed job runs
- Extract and categorize error patterns from job logs

**Key features:**
- All operations through structured scripts (no direct CLI access)
- JSON-first output for programmatic parsing
- Time-based and runner-based analysis
- Error pattern recognition and categorization
- Uses `glab` CLI directly through structured scripts

### 2. Konflux Release Skill

**Purpose:** Create production releases on the Konflux platform with a self-contained stage-to-production workflow.

**Use cases:**
- Create production releases from successful stage releases
- Query Konflux Release, Snapshot, and ReleasePlan resources
- Generate release YAMLs with release notes
- Orchestrate multi-component releases
- Follow stage-to-production deployment workflows

**Key features:**
- Self-contained skill with all commands inline (kubectl, glab, skopeo)
- Supports manual mode and config-driven mode with external product configs
- Automates stage-to-production release pattern
- Applies release notes templates with version/variant substitution
- Includes Python script for deterministic YAML generation
- Auto-increments release sequence numbers

### 3. AWS Log Analyzer Skill

**Purpose:** Troubleshoot and analyze logs from AWS CloudWatch Logs for debugging and monitoring.

**Use cases:**
- Investigate errors and exceptions across log groups
- Trace requests through multiple services
- Analyze performance issues and slow queries
- Monitor for specific error patterns in real-time
- Perform complex log aggregations and analysis

**Key features:**
- Supports CloudWatch Logs filter patterns and Insights queries
- Real-time log tailing with filtering
- Multi-log-group search capabilities
- Efficient time range handling (epoch conversion)
- Pretty-printing and JSON parsing with jq
- Helper scripts for common operations

### 4. GitLab Branch Manager Skill

**Purpose:** Create and protect GitLab branches for release workflows and branch management.

**Use cases:**
- Create release branches from main or a specific tag/ref
- Apply branch protection rules (push, merge, force push, unprotect restrictions)
- Verify branch protection configuration

**Key features:**
- Smart repo resolution (short name, full path, or URL)
- Extensible protection rules via parallel arrays + generic `--rule KEY=VALUE` flag
- Idempotent protection checks (matching rules succeed, differing rules fail)
- Dry-run mode for previewing actions
- JSON and human-readable output

## Prerequisites

Each skill has its own dependencies:

**GitLab Branch Manager Skill:**
- `glab` - GitLab CLI tool
- User already authenticated
- `jq` for JSON parsing

**GitLab Job Analyzer Skill:**
- `glab` - GitLab CLI tool (used internally by scripts)
- User already authenticated
- Optional: `jq` for JSON parsing

**Konflux Release Skill:**
- `kubectl` - Kubernetes operations
- `python3` + `PyYAML` for YAML generation script
- `jq` for JSON parsing
- Optional: `glab` for tag resolution, `skopeo` for image inspection

**AWS Log Analyzer Skill:**
- `aws` CLI - AWS CLI v2 recommended
- User already authenticated (IAM credentials, SSO, or instance profile)
- Optional: `jq` for JSON parsing and output formatting

## Installation

This plugin is configured in the marketplace at `.claude-plugin/marketplace.json` and can be loaded by Claude Code from the local `claudio-plugin` directory.

## Usage Philosophy

The skills follow these principles:

1. **Tool preference:** Use native CLI commands over API calls when possible
2. **Efficient querying:** Start with table output, drill down to specific resources
3. **Read-only by default:** Prefer GET operations for safety
4. **Integration:** Skills can work together or independently (e.g., Konflux Release is self-contained)
5. **Context efficiency:** Avoid dumping large JSON outputs unless necessary

## Example Workflows

### Production Release Workflow (Konflux Release Skill)

When a user asks to create a production release:

1. **Resolve tag to commit SHA**
   ```bash
   glab api --method GET "projects/owner%2Frepo/repository/commits/v1.2.3" | jq -r '.id'
   ```

2. **Find stage releases by SHA**
   ```bash
   kubectl get releases -n namespace -l "pac.test.appstudio.openshift.io/sha=<full-sha>"
   ```

3. **Filter to successful releases**
   - Check `.status.conditions[type=Released].status = "True"`

4. **Generate production YAMLs**
   ```bash
   /full/path/to/generate_release_yaml.py --component my-comp --version 1.2.3 --snapshot snap-abc --release-plan my-app-prod --release-name my-comp-1-2-3-prod-1 --accelerator Variant --namespace my-ns --release-notes-template /path/to/template.yaml --release-type RHEA --output out/component-prod.yaml
   ```

5. **Deliver for review** - commit generated files and open MR (config-driven) or deliver locally (manual)

### Log Troubleshooting Workflow (AWS Log Analyzer)

When a user asks to investigate application errors:

1. **Identify the log group**
   ```bash
   aws logs describe-log-groups --log-group-name-prefix /aws/application/
   ```

2. **Search for recent errors**
   ```bash
   scripts/time_range.sh "1 hour ago"
   aws logs filter-log-events \
     --log-group-name /aws/application/myapp \
     --filter-pattern "ERROR" \
     --start-time $START_TIME \
     --end-time $END_TIME
   ```

3. **Correlate with pod events**
   ```bash
   kubectl get events --sort-by='.lastTimestamp'
   ```

4. **Trace request across services**
   ```bash
   scripts/multi_group_search.sh "request-id-12345" "/aws/application/"
   ```

5. **Analyze error patterns**
   ```bash
   aws logs start-query \
     --log-group-name /aws/application/myapp \
     --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | stats count() by @message'
   ```

## Performance Optimization for Cross-Skill Analysis

When combining multiple skills (especially `gitlab-job-analyzer` + `aws-log-analyzer`), follow these optimization guidelines to minimize execution time and cost.

### Key Principles

**Think in parallel, execute in bulk, analyze once.**

1. **Maximum Parallelization** - Call all independent tools in ONE message
2. **Parse JSON Directly** - Use jq on outputs instead of multiple queries
3. **Eliminate Redundant Calls** - Extract data from existing results
4. **Smart Targeting** - Analyze first, then target specific resources
5. **Keep Using Skills** - Skills delegate to cheaper Haiku models

### Optimization Patterns

#### Pattern 1: Parallel Data Collection

**❌ Sequential (Slow - 10+ minutes):**
```bash
# Step 1: Get GitLab data
./gitlab-job-analyzer/scripts/analyze_recent_jobs.sh owner/repo --hours 24

# Wait for results...

# Step 2: Get AWS data
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/component1 24

# Wait for results...

# Step 3: Get more AWS data
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/component2 24
```

**✅ Parallel (Fast - 3-4 minutes):**
```bash
# Execute ALL independent calls in ONE message with multiple tool invocations:
# Tool 1: GitLab analysis
./gitlab-job-analyzer/scripts/analyze_recent_jobs.sh owner/repo --hours 24

# Tool 2: AWS component 1 analysis (independent of GitLab)
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/component1 24

# Tool 3: AWS component 2 analysis (independent of GitLab)
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/component2 24
```

**When to use parallel execution:**
- Data sources are independent (GitLab + AWS, multiple log groups, multiple repos)
- No data dependency between calls
- You need comprehensive analysis across multiple systems

**Implementation:**
- Make multiple Bash tool calls in a single message
- Each call executes independently and concurrently
- Results arrive together, reducing total wait time

#### Pattern 2: JSON Parsing Without Redundant Calls

**❌ Multiple calls for different data (Wasteful):**
```bash
# Call 1: Get total errors
./scripts/analyze_recent_jobs.sh owner/repo --hours 24 | jq '.job_statistics.failed'

# Call 2: Get runner breakdown (same data, called again!)
./scripts/analyze_recent_jobs.sh owner/repo --hours 24 | jq '.by_runner_tag'

# Call 3: Get stage breakdown (same data, called again!)
./scripts/analyze_recent_jobs.sh owner/repo --hours 24 | jq '.by_stage'
```

**✅ Single call, multiple parses (Efficient):**
```bash
# Step 1: Capture output ONCE
OUTPUT=$(./scripts/analyze_recent_jobs.sh owner/repo --hours 24)

# Step 2: Parse different fields from the same data
echo "$OUTPUT" | jq '.job_statistics.failed'
echo "$OUTPUT" | jq '.by_runner_tag'
echo "$OUTPUT" | jq '.by_stage'
echo "$OUTPUT" | jq '.failed_jobs[] | select(.runner_tag | startswith("aipcc-"))'
```

**Benefits:**
- 70% reduction in GitLab API calls
- Faster execution (no network round-trips)
- Lower cost (fewer tool invocations)

#### Pattern 3: Eliminate Redundant Scripts

**❌ Running overlapping scripts:**
```bash
# analyze_recent_jobs.sh already includes runner breakdown
./scripts/analyze_recent_jobs.sh owner/repo --hours 24

# analyze_by_runner.sh duplicates the same data
./scripts/analyze_by_runner.sh owner/repo --hours 24  # REDUNDANT
```

**✅ Extract from comprehensive output:**
```bash
# Single call gets all data
OUTPUT=$(./scripts/analyze_recent_jobs.sh owner/repo --hours 24)

# Extract runner-specific analysis with jq
echo "$OUTPUT" | jq '.by_runner_tag[] | {tag, total, failed, success_rate}'
echo "$OUTPUT" | jq '.failed_jobs[] | group_by(.runner_tag) | map({runner: .[0].runner_tag, count: length})'
```

**When analyze_by_runner.sh IS useful:**
- Need detailed runner comparison metrics not in analyze_recent_jobs.sh
- Need `--compare` flag for specific runner comparisons
- Need runner-specific duration statistics

**Rule of thumb:**
- If data exists in first script output → use jq to extract it
- If data requires different analysis logic → use specialized script

#### Pattern 4: Smart Targeting

**❌ Analyze everything upfront:**
```bash
# Analyze ALL 9 runner types without knowing which failed
./scripts/analyze_errors.sh /aws/runner/aipcc-small-x86_64 24
./scripts/analyze_errors.sh /aws/runner/aipcc-small-aarch64 24
./scripts/analyze_errors.sh /aws/runner/aipcc-medium-x86_64 24
# ... 6 more runner types
```

**✅ Identify problems first, then target:**
```bash
# Step 1: Get GitLab analysis (identify problematic runners)
GITLAB_OUTPUT=$(./scripts/analyze_recent_jobs.sh owner/repo --hours 24)

# Step 2: Extract runners with high failure rates
PROBLEM_RUNNERS=$(echo "$GITLAB_OUTPUT" | jq -r '.by_runner_tag[] | select(.failed > 5) | .tag')

# Step 3: Analyze AWS logs ONLY for problematic runners
# Make parallel calls for each problem runner
for runner in $PROBLEM_RUNNERS; do
  ./scripts/analyze_errors.sh /aws/runner/$runner 24
done
```

**Benefits:**
- Analyze only relevant resources (2-3 runners instead of 9)
- 60% reduction in AWS CloudWatch Logs Insights queries
- Faster results and lower cost

#### Pattern 5: Efficient Skill Usage

**✅ Keep using skills (they use cheaper Haiku models):**
```bash
# Preferred: Use skills - they delegate to Haiku ($0.05 per task)
# Skills handle tool installation, error handling, and best practices
./gitlab-job-analyzer/scripts/analyze_recent_jobs.sh owner/repo --hours 24
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/myapp 24
```

**❌ Don't bypass skills to call tools directly:**
```bash
# Anti-pattern: Direct tool calls bypass skill optimizations
glab api ...  # Missing skill logic, uses Sonnet context
aws logs start-query ...  # No error handling, uses Sonnet context
```

**Why skills are better:**
- Skills invoke specialized Haiku agents for heavy work
- Sonnet usage: $15/M output tokens
- Haiku usage: $1.25/M output tokens
- Skills = 12x cheaper for analysis tasks

### Complete Optimization Workflow

**Scenario:** "Analyze CI/CD failures and correlate with application logs for the last 24 hours"

**✅ Optimized Execution (3-4 minutes, ~$0.75-0.85):**

```bash
# SINGLE MESSAGE - All parallel tool calls:

# Tool 1: GitLab comprehensive analysis (identifies problem areas)
./gitlab-job-analyzer/scripts/analyze_recent_jobs.sh owner/repo --hours 24

# Tool 2: AWS log analysis for component 1 (independent)
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/component1 24

# Tool 3: AWS log analysis for component 2 (independent)
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/component2 24
```

**Then in subsequent analysis:**
```bash
# Parse GitLab results to identify problematic runners
GITLAB_OUTPUT=$(cat previous_output.json)  # From previous call
PROBLEM_RUNNERS=$(echo "$GITLAB_OUTPUT" | jq -r '.failed_jobs[] | .runner_tag' | sort | uniq)

# Parse AWS results to find error correlation
AWS_OUTPUT=$(cat aws_output.json)  # From previous call
echo "$AWS_OUTPUT" | jq '.top_errors[] | select(.count > 10)'

# Correlate: Match GitLab job failure times with AWS error spikes
echo "$GITLAB_OUTPUT" | jq '.failed_jobs[] | {time: .created_at, job: .name}'
echo "$AWS_OUTPUT" | jq '.hourly_distribution'
```

**❌ Non-Optimized Execution (10+ minutes, ~$1.06):**
- Sequential calls (wait for each to finish)
- Multiple calls to same script for different fields
- Analyze all resources before identifying problems
- Verbose explanations between each step

### Optimization Checklist

**Before starting analysis:**
- [ ] Identify all independent data sources (GitLab, AWS, K8s, etc.)
- [ ] Plan to fetch them in parallel (single message, multiple tools)
- [ ] Know which jq filters you'll need for parsing
- [ ] Target only necessary resources (not all runners/log groups)

**During execution:**
- [ ] Make ONE message with 4-6 parallel tool calls
- [ ] Use Skills for analysis scripts (not direct Bash)
- [ ] Capture full JSON outputs for later parsing
- [ ] Skip redundant data fetching

**After results:**
- [ ] Parse JSON with jq for different views
- [ ] Provide comprehensive analysis once
- [ ] Be concise with explanations

### Expected Performance

**Optimized vs Non-Optimized:**

| Metric | Non-Optimized | Optimized | Improvement |
|--------|---------------|-----------|-------------|
| **Time** | 10 minutes | 3-4 minutes | 60-70% faster |
| **Cost** | $1.06 | $0.75-0.85 | 25-30% cheaper |
| **Tool Calls** | 13+ calls | 4-5 calls | 65% fewer |
| **Context Usage** | High (repeated data) | Low (single fetch) | 40% reduction |

### Advanced Tips

**1. Batch Context Operations**
- Fewer conversation turns = less context repetition
- Make decisions upfront, execute in bulk
- Even cached tokens have cost

**2. Skip Exploratory Calls**
- Trust tool outputs on first try
- No "let me check the structure" calls
- Read skill documentation instead

**3. Reduce Verbose Outputs**
- Front-load all parallel calls
- Explain comprehensively once at the end
- Minimize intermediate commentary

**4. Use State Management Wisely**
- For typical analyses (10K errors, 200 jobs), direct JSON output is efficient
- Only save state for 100K+ entries or multi-day workflows
- State management adds complexity without benefit for normal datasets

## License

Apache License 2.0 - See LICENSE file for details.

## Author

Claudio (v0.1.0)
