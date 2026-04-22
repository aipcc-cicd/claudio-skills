---
name: weekly-status
description: Generate a weekly project status update paragraph for stakeholders. Looks at what shipped to production (git tags in the past 7 days), what is staged but not yet released (commits on main after the latest tag), and what the team is currently working on (active Jira sprint). Produces a single concise paragraph suitable for a status email or report. Use when the user asks for a status update, weekly report, or project summary.
compatibility: Requires a git repository. Jira credentials must be set as standard env vars (JIRA_SITE, JIRA_EMAIL, JIRA_TOKEN). jira-utilities skill must be available (acli and jq installed).
allowed-tools: Bash(git -C:*),Bash(git log:*),Bash(git tag:*),Bash(git describe:*),Bash(git rev-list:*),Bash(date:*),Bash(*/jira-utilities/scripts/*.sh:*),Bash(jq:*)
---

# Weekly Status Update

Generates a concise stakeholder-facing status paragraph covering: what shipped to production, what is staged, and what the team is actively working on.

## Credentials

Jira credentials are resolved in this order:

**1. Standard environment variables (preferred)** — set these in your shell or Claude Code session:

```bash
export JIRA_SITE=yourorg.atlassian.net   # no https:// prefix
export JIRA_EMAIL=you@example.com
export JIRA_TOKEN=your-api-token
```

## Parameters

Collect from the user's message or ask before proceeding:

1. **Repo path** (optional) — defaults to the current working directory. Only needed if running from outside the repo.
2. **Jira project key** (optional) — defaults to `AIPCC`.
3. **Jira component** (optional) — defaults to `AIPCC Productization`.
4. **Jira initiative/epic key** (optional) — the parent epic/initiative that scopes which sprint cards belong to this project. If not provided, it is discovered automatically (see step 0 below).
5. **Jira board name substring** (optional) — disambiguate if multiple boards exist for the project.

Use `.` as the repo path when not explicitly provided. All git commands must use `-C <repo_path>` so they work correctly regardless of working directory.

## Steps

### 0. Discover the initiative key (skip if already provided)

If no initiative key was passed, derive it from the repo name and look it up in Jira. Do this BEFORE step 1.

```bash
# Get repo name from git remote URL (e.g. "dashboard" from .../dashboard.git)
REPO_NAME=$(git -C <repo_path> remote get-url origin 2>/dev/null | sed 's/.*\///' | sed 's/\.git$//')
echo "Repo name: $REPO_NAME"
```

Then in the same Bash call load credentials and search for a matching initiative/epic:

```bash
echo "$JIRA_TOKEN" | acli jira auth login \
  --site "$JIRA_SITE" --email "$JIRA_EMAIL" --token 2>&1

acli jira workitem search \
  --jql "project = <PROJECT_KEY> AND issuetype in (Initiative, Epic) AND summary ~ \"$REPO_NAME\" ORDER BY created DESC" \
  2>&1 | head -60
```

Pick the most relevant result (the one whose summary best matches the repo name) and use its key as the initiative key for step 1. If nothing is found, proceed without the epic filter and note it in the output.

### 1. Gather git data and Jira sprint data in parallel

Run ALL of the following in a **single message** with multiple parallel Bash tool calls:

**Git call A — recent production releases (tags from last 7 days):**
```bash
git -C <repo_path> log --tags --simplify-by-decoration \
  --pretty=format:"%D|||%s" \
  --since="7 days ago" | grep "tag:" | \
  sed 's/.*tag: \([^,)]*\).*/\1|||/' | head -20
```
If that gives no output, also try:
```bash
git -C <repo_path> tag --sort=-creatordate \
  --format='%(creatordate:short) %(refname:short)' | \
  awk -v cutoff="$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)" \
  '$1 >= cutoff {print $2}'
```
For each tag found, get the commit message subjects it covers (since the previous tag):
```bash
git -C <repo_path> log <prev_tag>..<tag> --oneline --no-decorate 2>/dev/null | head -20
```

**Git call B — staged but unreleased work (commits on main after the latest tag):**
```bash
LATEST_TAG=$(git -C <repo_path> describe --tags --abbrev=0 HEAD 2>/dev/null || echo "")
if [ -n "$LATEST_TAG" ]; then
  git -C <repo_path> log "${LATEST_TAG}..HEAD" --oneline --no-decorate | head -20
else
  git -C <repo_path> log --oneline --no-decorate | head -20
fi
```

**Jira call — active sprint issues:**

Credential loading and the `acli` call MUST be in the same Bash command (exports do not persist across tool calls). Use this pattern as a single Bash call, substituting the real values for `<PROJECT_KEY>` and `<COMPONENT>`:

```bash
# Authenticate acli (credentials are visible in this shell process)
echo "$JIRA_TOKEN" | acli jira auth login \
  --site "$JIRA_SITE" \
  --email "$JIRA_EMAIL" \
  --token 2>&1

# Build JQL and search directly with acli
# Try parent field first (Jira Cloud next-gen), fall back to Epic Link (classic)
COMPONENT_FILTER=""
[ -n "<COMPONENT>" ] && COMPONENT_FILTER="AND component = \"<COMPONENT>\""
EPIC_FILTER=""
[ -n "<INITIATIVE_KEY>" ] && EPIC_FILTER="AND \"Epic Link\" = <INITIATIVE_KEY>"
JQL="project = <PROJECT_KEY> AND sprint in openSprints() $COMPONENT_FILTER $EPIC_FILTER"

acli jira workitem search --jql "$JQL" 2>&1 | head -150

# If the above returns 0 results and an initiative key was used, retry without the epic filter
# to avoid missing data — but flag it so the synthesis step knows to filter manually
```

### 2. Analyze and synthesize

From the git and Jira data:

**Production (shipped in the last 7 days):**
- Identify tags created within 7 days
- Summarize the user-facing changes from their commit messages — focus on features, improvements, and notable fixes
- Skip pure chores (dependency bumps, CI config tweaks, linting fixes) unless nothing else shipped

**Staged (committed to main, not yet released):**
- These are commits after the latest tag — they are on staging but not production
- Summarize what the team is working toward in the next release

**In progress (from Jira sprint):**
- Pull issue summaries from the active sprint
- **Only include items that are clearly about this project** (the one in the git repo). If a ticket is about a different product, a different tool, or a release coordination task for another product, discard it even if it appeared in the Jira results — the epic/initiative JQL filter may not catch everything.
- Focus on: new features, user-facing improvements, and any items not already covered by git data
- Include tech debt only if it has a meaningful user impact
- Skip purely internal tasks (test fixes, CI, refactors with no user impact) unless nothing else is in-sprint

### 3. Write the status paragraph

Produce **one paragraph** with these characteristics:
- **Length**: 3–5 sentences, strictly under 110 words
- **Tone**: professional, stakeholder-friendly — no jargon, no internal ticket IDs, no branch names
- **Structure**: lead with what the team shipped this week, then close with what the team is focusing on next (from in-progress/staged work)
- **Focus**: features and user-visible improvements first; tech debt may be mentioned briefly but should not dominate
- **Tense**: past tense for shipped, present/future for in-progress
- **No version numbers**: never mention tag names, version numbers, or release numbers (e.g. do not write "v1.8.1" or "version 1.8.1")
- **No release mentions**: never say "release", "shipped a release", "two releases", etc. — just describe what changed as things that happened "this week". Stakeholders don't care about how many releases were cut.
- **No product name**: never mention the product name (e.g. "CI/CD Dashboard", "the dashboard") — use "the team" as the subject instead (e.g. "the team shipped", "the team is working on").

**Examples of the target style:**
> The Package Checker has received a performance boost, providing much faster results through optimized backend processing. We also launched a new Releases tab for Builder Images, which allows users to browse tagged releases with component version matrices, architecture parameters, and release highlights. Our next priorities include adding automated changelogs for RHAIIS and base images and developing a new Support Matrix feature, with more details to follow soon.

> The package checker is now live with an improved interface, alongside a more accurate time-tracking feature. The dashboard also now includes the source branch for artifacts. We also improved the UI with better pagination and a data freshness indicator while resolving data consistency issues. Looking ahead, we are focusing on a dedicated builder image release view and a new support matrix page.

> A new time-tracking view is now available for both drops and series. This feature provides a clear, step-by-step breakdown of the release process, making it easy to understand exactly how much time each release took from start to finish. Meanwhile, we continue our ongoing work to fine-tune the package request form, alongside with the implementation of new features.

Output only the paragraph — no headers, no bullet points, no preamble.
