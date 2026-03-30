---
name: release-delta
description: Generate comprehensive release changelog documentation between two builder versions. Accepts old_version and new_version as arguments.
---

# Release Delta Generator

Generate comprehensive release changelog documentation between two versions of the AIPCC Wheels Builder.

## Parameters

- `old_version`: The starting version (e.g., v26.0.0)
- `new_version`: The ending version (e.g., v26.4.0)
- `--sections` (optional): Comma-separated list of sections to include in the output

### Available Sections

- `header` - Header section with dates, commits, releases count
- `timeline` - Release Timeline Table
- `highlights` - Key Highlights Section (executive summary)
- `releases` - Individual Release Sections (detailed notes)
- `summary` - Summary by Category
- `impact` - Impact Analysis
- `jira` - JIRA Issues Addressed
- `upgrade` - Upgrade Notes
- `contributors` - Contributors
- `references` - References
- `all` - All sections (default if --sections not specified)

## Usage

```bash
# Full report (all sections)
/release-delta v26.0.0 v26.4.0

# Only key highlights
/release-delta v26.0.0 v26.4.0 --sections highlights

# Multiple specific sections
/release-delta v26.0.0 v26.4.0 --sections header,timeline,highlights

# Executive summary (header + timeline + highlights)
/release-delta v26.0.0 v26.4.0 --sections header,timeline,highlights,impact

# Quick overview (no detailed releases)
/release-delta v26.0.0 v26.4.0 --sections header,timeline,highlights,summary,upgrade
```

## Instructions

When this skill is invoked:

1. **Parse the parameters** from the skill arguments:
   - Extract old_version and new_version
   - Extract --sections parameter if provided (defaults to "all")
   - Parse sections into a list (e.g., "header,timeline,highlights" → ["header", "timeline", "highlights"])
   - If old_version or new_version not provided, ask the user for them using AskUserQuestion
   - Validate section names against available sections list

2. **Update the repository**:
   - Run `git fetch --tags upstream` to get latest tags from upstream
   - Run `git pull upstream main` to update main branch

3. **Validate versions**:
   - Verify both version tags exist in the repository
   - If either tag doesn't exist, inform the user and list available recent tags

4. **Collect release information**:
   - Get the list of all version tags between old_version and new_version (inclusive of new_version, exclusive of old_version)
   - For each release tag:
     - Get the release date: `git log -1 --format='%ad' --date=short <tag>`
     - Get the tagger: `git for-each-ref --format='%(taggername) <%(taggeremail)>' refs/tags/<tag>`
     - Get the release notes: `git show <tag> --no-patch --format="%N" | tail -n +3`
     - Get the commit hash: `git log -1 --format="%H" <tag>`

5. **Collect commit details**:
   - Get all commits between versions: `git log <old_version>..<new_version> --oneline --no-merges --reverse`
   - Count total commits: `git log <old_version>..<new_version> --oneline --no-merges | wc -l`

6. **Generate the changelog document** based on requested sections:
   - If --sections is "all" or not specified, include all sections
   - Otherwise, only include the sections specified in the --sections parameter
   - Always maintain the order: header → timeline → highlights → releases → summary → impact → jira → upgrade → contributors → references → footer

   **Section Definitions:**

   **Header Section (section: "header"):**
   - Title: "AIPCC Wheels Builder - Changelog <old_version> to <new_version>"
   - Period dates (start to end)
   - Total commits count
   - Total releases count
   - Repository URL: https://gitlab.com/redhat/rhel-ai/wheels/builder

   **Release Timeline Table (section: "timeline"):**
   - Columns: Version | Date | Released By | Type
   - List all releases chronologically

   **Key Highlights Section (section: "highlights"):**
   This executive summary section appears immediately after the Release Timeline Table and before detailed release notes.

   Structure:
   - **Introduction paragraph**: Brief overview of the release cycle's main themes

   - **Major Features:**
     - Group by category (e.g., "New Accelerator Platform Support", "vLLM Ecosystem Expansion", "Performance Optimizations")
     - Use bullet points with bold package/feature names and clear descriptions
     - Include specific version numbers and platform details

   - **Stability & Build Improvements:**
     - "PyTorch Ecosystem Constraints" section listing all constraint fixes
     - "Package Build Fixes" section listing resolved build issues
     - Use bullet points with package names in bold

   - **Enhanced Package Building:**
     - Highlight source-based builds and build system improvements
     - Note any new build capabilities

   - **Development Tools & Infrastructure:**
     - CI/CD improvements
     - Tooling updates
     - Developer experience enhancements

   - **Release Metrics:**
     - Number of releases and timespan
     - Total commits
     - JIRA tickets count
     - Major feature areas count
     - Release managers with contribution counts

   - **Impact Summary:**
     - 3-4 concise impact statements covering:
       - Platform/accelerator expansion
       - Ecosystem maturity
       - Production readiness
       - Performance improvements
     - Each statement: Bold topic followed by explanation (1-2 sentences)

   End with horizontal rule before "Detailed Release Notes" heading.

   **Individual Release Sections (section: "releases", newest first):**
   For each release:
   - Release version and date
   - Released by (name and email)
   - Commit hash
   - Features section (issues marked with [Feat])
   - Fixes section (issues marked with [Fix])
   - Other sections as needed (Chore, Refactor, etc.)
   - List of commit hashes with descriptions

   **Summary by Category (section: "summary"):**
   - Group all changes by type: Features, Bug Fixes, Maintenance
   - Provide high-level summaries of major changes
   - Organize by functional area (e.g., vLLM, CUDA, Torch ecosystem, etc.)

   **Impact Analysis (section: "impact"):**
   - Describe impact of major features
   - Note any breaking changes
   - Highlight platform/accelerator additions

   **JIRA Issues Addressed (section: "jira"):**
   - Count unique JIRA issues
   - Group by component/area

   **Upgrade Notes (section: "upgrade"):**
   - Breaking changes (if any)
   - New features available
   - Important constraints to note
   - Recommended actions

   **Contributors (section: "contributors"):**
   - List release managers and contribution counts

   **References (section: "references"):**
   - Repository URL
   - Release page URL
   - Documentation references

   **Footer (always included):**
   - Generation date
   - Source (git tag range)

7. **Save the document**:
   - Create filename based on sections:
     - If all sections: `RELEASE_CHANGES_<old_version>_to_<new_version>.md`
     - If filtered sections: `RELEASE_CHANGES_<old_version>_to_<new_version>_<sections>.md`
       - Example: `RELEASE_CHANGES_v26.0.0_to_v26.4.0_highlights.md`
       - For multiple sections: `RELEASE_CHANGES_v26.0.0_to_v26.4.0_highlights-summary.md`
   - Save to the current working directory
   - Inform the user of the file location

8. **Summary**:
   - Provide a brief summary of what was generated
   - Include: number of releases, date range, sections included
   - If only specific sections were requested, mention which sections were included
   - Show the file path as a clickable link

## Output Format

The generated document should be in Markdown format, well-structured, and suitable for Product Owner review and sprint reporting.

## Error Handling

- If git fetch fails, inform the user and suggest checking network/credentials
- If version tags don't exist, list recent available tags
- If no commits found between versions, inform the user
- If upstream remote doesn't exist, suggest adding it with:
  ```
  git remote add upstream git@gitlab.com:redhat/rhel-ai/wheels/builder.git
  ```

## Notes

- This skill focuses on the upstream repository at `git@gitlab.com:redhat/rhel-ai/wheels/builder.git`
- Include all commit details and JIRA ticket references for traceability
- Organize information for easy scanning by Product Owners and stakeholders

### Section Filtering Behavior

- **Default (no --sections)**: Generate full report with all sections
- **--sections all**: Explicitly generate full report (same as default)
- **--sections <specific>**: Generate only the requested sections
- **Data collection**: Always collect all data regardless of sections requested (needed for cross-references)
- **Section order**: Always maintain the canonical order even when filtering
- **Footer**: Always included regardless of section filtering
- **Invalid sections**: If an invalid section name is provided, inform the user and list valid options

## Key Highlights Section Example

The Key Highlights section should be comprehensive yet scannable. Use the following structure:

```markdown
## Key Highlights

This release cycle (vX.X.X to vY.Y.Y) introduces [main themes].

### Major Features

#### Category Name
- **Package/Feature Name** - Description with specifics
- **Another Feature** - Details including versions and platforms

### Stability & Build Improvements

#### PyTorch Ecosystem Constraints (N fixes)
Critical version constraints to ensure reproducible, stable builds:

- **Package**: Constraint details
- **Another Package**: Constraint details

#### Package Build Fixes
- **package-name**: Fix description
- **another-package**: Fix description

### Enhanced Package Building

#### Source-Based Builds
- **packages**: Description
  - Additional details
  - More context

### Development Tools & Infrastructure
- **Tool/Area**: Description
- **Another Area**: Description

### Release Metrics

- **N releases** over X days (Date1 - Date2)
- **N commits** with no merges
- **N+ JIRA tickets** resolved across multiple components
- **N major feature areas**: Area1, Area2, Area3
- **N release managers**: Name1 (X releases), Name2 (Y releases)

### Impact Summary

**Topic**: One to two sentence explanation of impact and importance.

**Another Topic**: Description of significance and benefit.

**Third Topic**: Explanation of improvement or addition.

**Fourth Topic**: Impact statement with specific details.
```
