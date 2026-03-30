# Claudio Skills Plugin

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.4.0-green.svg)](claudio-plugin/.claude-plugin/plugin.json)

A Claude Code plugin that extends Claude with specialized skills for DevOps and cloud-native development workflows.

## Overview

Claudio Skills Plugin provides five production-ready skills designed to streamline interactions with GitLab CI/CD, Konflux, AWS CloudWatch Logs, Slack, and GitLab branch management. Each skill provides Claude Code with domain-specific capabilities, allowing you to leverage Claude as an intelligent assistant for complex DevOps tasks.

## Features

- **CI/CD Job Analysis** - Analyze GitLab pipeline failures, parse logs, and identify error patterns
- **Konflux Release Orchestration** - Automate stage-to-production release workflows on the Konflux platform
- **AWS Log Analysis** - Troubleshoot and analyze CloudWatch Logs with advanced querying
- **Slack Utilities** - Search messages, post updates, and interact with Slack workspaces
- **GitLab Branch Management** - Create and protect GitLab branches with configurable protection rules

## Skills

### 1. GitLab Job Analyzer Skill

Analyze GitLab CI/CD job failures with structured scripts and error pattern recognition.

**Use Cases:**
- Summarize job activity across pipelines in a time range
- Analyze failures by runner type
- Deep-dive into specific pipeline failures
- Compare successful vs failed job runs
- Extract and categorize error patterns from job logs

**Key Features:**
- JSON-first output for programmatic parsing
- Time-based and runner-based analysis
- Error pattern recognition and categorization
- Uses `glab` CLI directly through structured scripts

### 2. Konflux Release Skill

Work with Konflux - a build and release platform based on OpenShift and Tekton.

**Use Cases:**
- Create production releases from successful stage releases
- Query Konflux Release, Snapshot, and ReleasePlan resources
- Generate release YAMLs with release notes
- Orchestrate multi-component releases
- Follow stage-to-production deployment workflows

**Key Features:**
- Automates stage → production release pattern
- Deterministic YAML generation with Python scripts
- Self-contained with inline kubectl, glab, and skopeo commands
- Supports manual mode and config-driven mode with external product configs

### 3. AWS Log Analyzer Skill

Troubleshoot and analyze logs from AWS CloudWatch Logs.

**Use Cases:**
- Investigate errors and exceptions across log groups
- Trace requests through multiple services
- Analyze performance issues and slow queries
- Monitor for specific error patterns in real-time
- Perform complex log aggregations and analysis

**Key Features:**
- CloudWatch Logs filter patterns and Insights queries
- Real-time log tailing with filtering
- Multi-log-group search capabilities
- Efficient time range handling

### 4. Slack Utilities Skill

Interact with Slack workspaces using the Slack Web API.

**Use Cases:**
- Search messages across channels
- Post messages and updates
- List channels and conversations
- Retrieve conversation history

**Key Features:**
- Uses Slack Web API for programmatic access
- Supports message search and posting
- Channel and conversation management

To get values for them the easiest way is to authenticate to your slack workspace in chrome/chromium browser

On same page go to More Tools -> Developer Tools

On Developer Tools go to:

* XOXC: Application -> Storage -> Local Storage -> https>//app.slack.com -> localConfig_v2 (key) -> 'token' key inside the json value 
* XOXD: Application -> Storage -> Cookies -> https>//app.slack.com -> d (key)

Since it is slack enterpise we need to get value for User-Agent. To get it from same place we check Networking and check request headers to get the value,
it should be something similar to `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36`

Disclaimer, the first time you reuse those Tokens you will probably be signed off as precaution, the second time you sign in the tokens should last.

### 5. GitLab Branch Manager Skill

Create and protect GitLab branches for release workflows and branch management.

**Use Cases:**
- Create release branches from main or a specific tag/ref
- Apply branch protection rules (push, merge, force push, unprotect restrictions)
- Verify branch protection configuration

**Key Features:**
- Smart repo resolution (short name, full path, or URL)
- Extensible protection rules with generic `--rule KEY=VALUE` override
- Idempotent protection checks (matching rules succeed, differing rules fail)
- Dry-run mode for previewing actions
- JSON and human-readable output
- Compatible with bash 3.2+ (macOS, RHEL, Ubuntu, Alpine)

## Installation

### Prerequisites

**Core Requirements:**
- [Claude Code](https://claude.com/claude-code) CLI
- Git

**Skill-Specific Dependencies:**

Each skill manages its own dependencies through installer scripts in `claudio-plugin/tools/`:

| Skill | Required Tools | Auto-Installed |
|-------|---------------|----------------|
| GitLab Job Analyzer | `glab`, `jq` | `jq` only |
| Konflux Release | `kubectl`, `glab`, `skopeo`, `python3` + PyYAML, `jq` | `kubectl`, `skopeo`, `jq`, PyYAML |
| AWS Log Analyzer | `aws` CLI v2, `jq` | Both |
| Slack Utilities | `curl`, `jq`, `python3` + requests | `jq`, requests |
| GitLab Branch Manager | `glab`, `jq` | `jq` only |

**Authentication:**
- GitLab: Authenticate with `glab auth login` before using (required for GitLab Job Analyzer, GitLab Branch Manager, and Konflux Release)
- Kubernetes: Configure kubectl context with `kubectl config use-context` (required for Konflux Release)
- AWS: Authenticate with AWS CLI (`aws configure`, SSO, or instance profile)
- Slack: Configure API token (see skill documentation or MCP server integration)

### Install Plugin

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd claudio-plugin
   ```

2. The plugin will be automatically discovered by Claude Code from the `claudio-plugin` directory

3. Verify installation by invoking a skill in Claude Code

## Usage

### Basic Skill Invocation

Skills are invoked automatically by Claude Code when relevant to your request. You can also explicitly reference them:

```
# CI/CD analysis
"Analyze failed jobs in the last 24 hours for owner/repo"

# Konflux releases
"Create a production release for tag v1.2.3 in owner/repo"

# AWS log troubleshooting
"Find errors in /aws/application/myapp from the last hour"

# Slack operations
"Search for messages about 'deployment' in #engineering"

# Branch management
"Create a branch release-1.5 on aipcc-claudio"
```

### Example Workflows

#### Production Release Workflow

Using the Konflux Release skill:

```
"Create a production release for tag v1.2.3 in owner/repo"
```

Claude will:
1. Resolve the tag to a commit SHA using `glab`
2. Find successful stage releases using `kubectl`
3. Generate production release YAMLs with the Python script
4. Prepare release files for review (does not auto-apply)

#### Log Troubleshooting Workflow

Using the AWS Log Analyzer skill:

```
"Investigate errors in /aws/application/myapp from the last hour"
```

Claude will:
1. Search CloudWatch Logs for errors with time-range filtering
2. Extract and categorize error patterns
3. Analyze error distribution and provide actionable insights

#### CI/CD Failure Analysis

Using GitLab Job Analyzer skill:

```
"Analyze CI/CD failures for owner/repo in the last 24 hours, broken down by runner type"
```

Claude will:
1. Run comprehensive job analysis
2. Identify failure patterns by runner, stage, and error type
3. Provide actionable insights

#### Branch Management Workflow

Using the GitLab Branch Manager skill:

```
"Create a branch release-1.5 on owner/repo from tag v1.4.0"
```

Claude will:
1. Resolve the repository to its full GitLab project path
2. Create the branch from the specified ref
3. Apply protection rules (push blocked, merge by maintainers only, no force push, no unprotect)
4. Return JSON result with branch and protection details

## Architecture

```
claudio-plugin/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata
├── tools/
│   ├── common.sh                # Shared library for tool installers
│   ├── TOOLS.md                 # Tool installation guide
│   ├── aws-cli/
│   │   └── install.sh           # AWS CLI installer
│   ├── glab/
│   │   └── install.sh           # glab GitLab CLI installer
│   ├── jq/
│   │   └── install.sh           # jq installer
│   ├── kubectl/
│   │   └── install.sh           # kubectl installer
│   ├── python/
│   │   ├── install.sh           # Python pip installer
│   │   ├── konflux-release-requirements.txt
│   │   └── slack-requirements.txt
│   └── skopeo/
│       └── install.sh           # skopeo installer
└── skills/
    ├── gitlab-job-analyzer/
    │   ├── SKILL.md             # GitLab CI/CD job analysis skill
    │   └── scripts/             # Analysis scripts
    ├── konflux-release/
    │   ├── SKILL.md             # Konflux release workflow skill
    │   └── scripts/
    │       └── generate_release_yaml.py
    ├── aws-log-analyzer/
    │   ├── SKILL.md             # AWS CloudWatch Logs analysis skill
    │   └── scripts/             # Log analysis scripts
    ├── slack-utilities/
    │   ├── SKILL.md             # Slack Web API skill
    │   └── scripts/             # Slack interaction scripts
    └── gitlab-branch-manager/
        ├── SKILL.md             # GitLab branch creation and protection skill
        └── scripts/
            └── create_and_protect_branch.sh
```

## Tool Management

The `claudio-plugin/tools/` directory provides centralized installation scripts for CLI tools used by skills. This system ensures consistent, maintainable dependency management.

**Design Principles:**
- **Simplicity:** Scripts do one thing well - install the tool if not present
- **Reusability:** Common functions shared via `common.sh` library
- **Linux-only:** Focus on Linux x86_64 and ARM64 architectures
- **Idempotent:** Safe to run multiple times

**Available Tools:**
- `aws-cli/install.sh` - AWS CLI v2 installer
- `glab/install.sh` - glab GitLab CLI installer
- `jq/install.sh` - jq JSON processor installer
- `kubectl/install.sh` - kubectl Kubernetes CLI installer
- `python/` - Python package installers (pip-based requirements.txt files)
- `skopeo/install.sh` - skopeo container image inspector installer

**Adding New Tools:**

See `claudio-plugin/tools/TOOLS.md` for comprehensive guidelines on adding new tool installers.

## Performance Optimization

When using multiple skills together (especially GitLab Job Analyzer + AWS Log Analyzer), follow these optimization patterns:

1. **Maximum Parallelization** - Execute independent data fetches concurrently
2. **Parse JSON Directly** - Use `jq` on existing outputs instead of multiple queries
3. **Eliminate Redundant Calls** - Extract data from existing results
4. **Smart Targeting** - Analyze first, then target specific resources

See [CLAUDE.md](CLAUDE.md) for detailed optimization guidelines and performance benchmarks.

## Development

### Adding a New Skill

1. Create a directory under `claudio-plugin/skills/<skill-name>/`
2. Add a `SKILL.md` file with skill documentation
3. Add any required scripts under `scripts/`
4. Update `claudio-plugin/.claude-plugin/plugin.json` if needed
5. Add tool installers to `claudio-plugin/tools/` if dependencies are needed

### Testing

Each skill includes its own test scenarios. Run skill-specific scripts directly to test functionality:

```bash
# Test GitLab job analyzer
./claudio-plugin/skills/gitlab-job-analyzer/scripts/analyze_recent_jobs.sh owner/repo --hours 24

# Test AWS log analyzer
./claudio-plugin/skills/aws-log-analyzer/scripts/analyze_errors.sh /aws/application/myapp 24
```

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Comprehensive plugin documentation for Claude Code
- **[LICENSE](LICENSE)** - Apache License 2.0
- **[tools/TOOLS.md](claudio-plugin/tools/TOOLS.md)** - Tool installation guide

**Skill-Specific Documentation:**
- [GitLab Job Analyzer Skill](claudio-plugin/skills/gitlab-job-analyzer/SKILL.md)
- [Konflux Release Skill](claudio-plugin/skills/konflux-release/SKILL.md)
- [AWS Log Analyzer Skill](claudio-plugin/skills/aws-log-analyzer/SKILL.md)
- [Slack Utilities Skill](claudio-plugin/skills/slack-utilities/SKILL.md)
- [GitLab Branch Manager Skill](claudio-plugin/skills/gitlab-branch-manager/SKILL.md)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests and documentation
5. Submit a pull request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Author

Claudio (v0.1.0)

## Support

For issues, questions, or feature requests, please file an issue on the GitHub repository.
