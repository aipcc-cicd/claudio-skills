---
name: gitlab
description: Interact with GitLab repositories using the glab CLI tool. This skill should be used when the user provides GitLab URLs, asks to resolve git tags to commit SHAs, retrieve commit details, manage merge requests, issues, pipelines, or perform other GitLab repository operations. Uses the official GitLab CLI (glab).
allowed-tools: Bash(glab api --method GET:*)
---

# GitLab

## Overview

Interact with GitLab repositories using the `glab` CLI tool - the official GitLab command-line interface.

**Prerequisites:**
- `glab` command is available
- User is already authenticated
- Works with gitlab.com, GitLab Self-Managed, and GitLab Dedicated

**Philosophy:**
Always use glab's built-in commands first. Only fall back to `glab api` for operations not covered by built-in commands.

## Built-in Commands

### Merge Requests

```bash
glab mr list -R <owner>/<repo>                      # List MRs
glab mr view <mr-number> -R <owner>/<repo>          # View MR details
glab mr diff <mr-number> -R <owner>/<repo>          # View MR diff
glab mr create                                      # Create MR
glab mr approve <mr-number> -R <owner>/<repo>       # Approve MR
glab mr merge <mr-number> -R <owner>/<repo>         # Merge MR
glab mr note <mr-number> -m "comment" -R <owner>/<repo>  # Add comment
```

### Issues

```bash
glab issue list -R <owner>/<repo>                   # List issues
glab issue view <issue-number> -R <owner>/<repo>    # View issue details
glab issue create -R <owner>/<repo>                 # Create issue
glab issue note <issue-number> -m "comment" -R <owner>/<repo>  # Add comment
glab issue close <issue-number> -R <owner>/<repo>   # Close issue
```

### CI/CD Pipelines

```bash
glab ci list -R <owner>/<repo>                      # List pipelines
glab ci view <pipeline-id> -R <owner>/<repo>        # View pipeline details
glab ci status -R <owner>/<repo>                    # Check pipeline status
glab job list -R <owner>/<repo>                     # List jobs
glab job view <job-id> -R <owner>/<repo>            # View job details
```

### Releases

```bash
glab release list -R <owner>/<repo>                 # List releases
glab release view <tag> -R <owner>/<repo>           # View release details
glab release download <tag> -R <owner>/<repo>       # Download release assets
glab release create <tag> -R <owner>/<repo>         # Create release
```

### Repository Operations

```bash
glab repo view -R <owner>/<repo>                    # View repository details
glab repo clone <owner>/<repo>                      # Clone repository
glab repo contributors -R <owner>/<repo>            # List contributors
glab repo search -s <search-term>                   # Search repositories
```

### Other Useful Commands

```bash
glab label list -R <owner>/<repo>                   # List labels
glab variable list -R <owner>/<repo>                # List CI/CD variables
glab schedule list -R <owner>/<repo>                # List pipeline schedules
glab snippet list -R <owner>/<repo>                 # List snippets
```

## API Fallback (Use Only When Necessary)

For operations not covered by built-in commands, use `glab api` with `--method GET`:

```bash
# Get tags for a repository
glab api --method GET projects/<owner>%2F<repo>/repository/tags | jq -r '.[].name'

# Get commit SHA for a tag
glab api --method GET projects/<owner>%2F<repo>/repository/commits/<tag> | jq -r '.id'

# URL-encode the project path: / becomes %2F
```

**Important:** Always use `--method GET` to ensure read-only operations.

**When to use API:**
- Retrieving commit SHAs from tags (no built-in command for this)
- Accessing repository metadata not exposed by built-in commands
- Advanced queries requiring direct API access

**Prefer built-in commands when available:**
- ✅ Use `glab mr diff` instead of API for MR diffs
- ✅ Use `glab release view` instead of API for release details
- ✅ Use `glab ci view` instead of API for pipeline details

## Example Workflows

**Get commit SHA for a tag:**

User: "What's the commit SHA for tag v1.2.3 in https://gitlab.com/owner/project?"

```bash
# Extract owner/repo: owner/project
# No built-in command for tag->SHA, use API
glab api --method GET projects/owner%2Fproject/repository/commits/v1.2.3 | jq -r '.id'
```

**View merge request diff:**

User: "Show me the diff for MR !123 in gitlab-org/gitlab"

```bash
# Use built-in command
glab mr diff 123 -R gitlab-org/gitlab
```

**Check pipeline status:**

User: "What's the status of the latest pipeline in my project?"

```bash
# Use built-in command
glab ci status -R <owner>/<repo>
```

## Repository Specification

The `-R` flag specifies the repository:

```bash
-R <owner>/<repo>                    # gitlab.com repository
-R <group>/<subgroup>/<repo>         # Multi-level groups
-R https://gitlab.com/<owner>/<repo> # Full URL
```

If run from within a git repository directory, `-R` can be omitted and glab will auto-detect.

## GitLab Instances (Hosts)

For GitLab instances other than gitlab.com:

**Built-in commands** - Use full URL in `-R` flag:
```bash
glab mr view 123 -R https://gitlab.example.com/owner/repo
glab ci status -R https://gitlab.example.com/owner/repo
```

**API commands** - Use `--hostname` flag:
```bash
glab api --method GET projects/owner%2Frepo/repository/tags --hostname gitlab.example.com
```

**Important**:
- Built-in commands (mr, ci, issue, etc.) require full URL in `-R`
- API commands require `--hostname` flag

## Best Practices

**Command preference:**
- Always use built-in glab commands first
- Only use `glab api` for operations not covered by built-in commands
- Built-in commands provide better output formatting and error handling

**Using the API (when necessary):**
- Always use `--method GET` to ensure read-only operations
- URL-encode project paths (replace `/` with `%2F`)
- Use jq for JSON parsing: `glab api --method GET ... | jq -r '.field'`
- Reference: https://docs.gitlab.com/api/

**Repository specification:**
- Always specify `-R` for clarity unless in a git directory
- Use full paths for subgroups: `parent-group/child-group/project`
- For non-gitlab.com instances:
  - Built-in commands: Use full URL in `-R` (e.g., `-R https://gitlab.example.com/owner/repo`)
  - API commands: Use `--hostname` flag (e.g., `--hostname gitlab.example.com`)

## Dependencies

**Required:**
- `glab` - GitLab CLI tool

**Optional:**
- `jq` - JSON processor for parsing API responses
