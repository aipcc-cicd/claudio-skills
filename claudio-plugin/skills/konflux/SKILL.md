---
name: konflux
description: Work with Konflux releases and deployments. This skill should be used when the user asks about creating production releases, querying Konflux resources, or understanding the stage-to-production release workflow. Covers Release, Snapshot, and ReleasePlan concepts.
---

# Konflux

## Overview

Work with Konflux - a build and release platform based on OpenShift and Tekton.

**Prerequisites:**
- kubectl/kubernetes skill for querying resources
- gitlab skill for resolving tags to commit SHAs
- Release notes template YAML file (required for production releases)

**Scripts:**
This skill includes helper scripts in `scripts/`.

Execute scripts using the full path constructed from skill path + relative path:
```bash
{skill_path}/scripts/generate_release_yaml.py [args]
```

**Path Construction:**
- When the skill is invoked, you have access to the skill path
- Join the skill path with the relative script path: `scripts/generate_release_yaml.py`
- Example: If skill path is `/home/user/.claude/skills/konflux`, then script path is `/home/user/.claude/skills/konflux/scripts/generate_release_yaml.py`

**IMPORTANT:** When executing scripts, MUST construct the full path from skill path, use single-line commands with NO line breaks, and call the script directly (not via `python`). See Step 4 for detailed execution requirements.

**Core Concepts:**
- **Release**: A deployment of a specific snapshot to an environment
- **Snapshot**: A point-in-time collection of component versions
- **ReleasePlan**: Defines how and where releases are deployed
- **Application**: Group of related components
- **Component**: Individual buildable/deployable unit

## Release Workflow Pattern

### Stage → Production Pattern

Most Konflux applications follow this pattern:

```
1. Code merged → CI builds → Stage Release created
2. Stage Release succeeds → Snapshot captured
3. Manual Production Release created → References same Snapshot
4. Production Release deploys to production environment
```

**Key principle:** Stage and Prod releases reference the same Snapshot for consistency.

## Creating Production Releases

### Workflow Overview

**Starting point:** Git tag or commit SHA

**Steps:**
1. **Resolve tag to SHA** (if needed) - use gitlab skill
2. **Find stage releases** by SHA label - use kubernetes skill
3. **Filter to successful stage releases** - check status, report failures, continue with successes only
4. **Generate production release YAMLs** - use `{skill_path}/scripts/generate_release_yaml.py` for each successful release
5. **Apply YAMLs to cluster** - deploy releases

### Step 1: Resolve Tag to Commit SHA

Use the **gitlab skill** to resolve a tag to its full 40-character commit SHA.

### Step 2: Find Stage Releases by SHA

Use the **kubernetes skill** to query releases with label selector:

```bash
kubectl get releases -n <namespace> \
  -l "pac.test.appstudio.openshift.io/sha=<full-40-char-sha>"
```

**Important:**
- Use the **full 40-character SHA** in the label selector
- Stage releases are labeled with the commit SHA
- Each component has its own release object

### Step 3: Filter to Successful Stage Releases

Use the **kubernetes skill** to check the status of each stage release.

Check that `.status.conditions[type=Released].status = "True"` for each release.

**Filter to only successful releases:**
- Identify which stage releases have succeeded
- Report any failed releases to the user
- Continue with ONLY the successful releases for production YAML generation
- Do NOT generate production YAMLs for failed stage releases

### Step 4: Generate Production Release YAMLs

Use the provided script to generate prod release YAML with all parameters provided directly:

```bash
{skill_path}/scripts/generate_release_yaml.py \
  --component <component-name> \
  --version <semantic-version> \
  --snapshot <snapshot-name> \
  --release-plan <prod-release-plan> \
  --release-name <prod-release-name> \
  --accelerator <accelerator-or-variant> \
  --namespace <namespace> \
  --release-notes-template <path-to-template.yaml> \
  --release-type <RHEA|RHSA> \
  --cves-file <path-to-cves-file> \
  --output out/<component>-prod.yaml
```

**CRITICAL EXECUTION REQUIREMENTS:**
- **MUST construct the full path: `{skill_path}/scripts/generate_release_yaml.py`**
- **MUST execute as a single-line command with NO line breaks**
- **MUST execute the script directly via Bash - DO NOT use `python` or `python3` prefix**
- Line breaks in the command will cause permission errors
- The script is executable and has a shebang, so call it directly
- When the skill is invoked, you have access to the skill path - join it with `scripts/generate_release_yaml.py`

**Correct:**
```bash
{skill_path}/scripts/generate_release_yaml.py --component cuda-ubi9 --version 3.2.5 --snapshot my-app-78c7f --release-plan my-product-ubi9-prod --release-name my-product-cuda-ubi9-3-2-5-prod-4 --accelerator CUDA --namespace my-namespace --release-notes-template /tmp/ga-rhea.yaml --release-type RHEA --output out/release.yaml
```

**Incorrect:**
```bash
# DO NOT USE - Has line breaks
{skill_path}/scripts/generate_release_yaml.py \
  --component cuda-ubi9 \
  --version 3.2.5

# DO NOT USE - Uses python prefix
python {skill_path}/scripts/generate_release_yaml.py --component cuda-ubi9 ...

# DO NOT USE - Using relative path without skill_path
scripts/generate_release_yaml.py --component cuda-ubi9 ...
```

**Script features:**
- Takes all parameters directly (no kubectl queries)
- Applies release notes template with {version} and {accelerator} substitutions
- Completely generic - no product or release type awareness
- User controls everything via parameters (ReleasePlan, template, etc.)
- Supports RHSA releases with CVE lists via `--cves-file`
- Deterministic YAML output

**Required parameters:**
- Component name - for CVE component field
- Snapshot name - from successful stage release
- Release plan name - **user chooses appropriate plan (GA vs TP have different plans)**
- Release name - must be unique
- Accelerator/variant - for template substitution
- Semantic version - for template substitution
- Release notes template - **user chooses appropriate template (GA vs TP have different templates)**

**Important:** The script doesn't distinguish between GA and Tech Preview releases. The user is responsible for passing the correct ReleasePlan name and template file for their release type.

### Step 5: Deploy Production Releases

Apply generated YAMLs:

```bash
kubectl apply -f out/
```

Monitor release status:

```bash
kubectl get releases -n <namespace> -w
```

## Release Notes Templates

### Template File Format

Products provide release notes templates as YAML files. Different release types require different templates and ReleasePlans:

**Example GA Template (ga-rhea.yaml):**
```yaml
type: RHEA
synopsis: "Product Name {version} ({accelerator})"
description: "Product Name"
topic: "Product Name {version} ({accelerator}) is now available."
references:
  - https://example.com/product
solution: ""
```
*For GA releases, also use: `--release-plan my-product-ga-prod`*

**Example Tech Preview Template (tp-rhea.yaml):**
```yaml
type: RHEA
synopsis: "Product Name Tech Preview {version} ({accelerator})"
description: "Product Name Tech Preview"
topic: "Product Name Tech Preview {version} ({accelerator}) is now available."
references:
  - https://example.com/product
solution: ""
```
*For TP releases, also use: `--release-plan my-product-tp-prod`*

**Template Variables:**
- `{version}`: Provided via `--version` argument (e.g., "3.2.5")
- `{accelerator}`: Provided via `--accelerator` argument (e.g., "CUDA", "ROCm", "CPU")

**Variable Substitution:**
- The script replaces all `{version}` and `{accelerator}` placeholders in template strings
- Works recursively through all string values in the template

**User Responsibility:**
- Choose the correct template file for your release type
- Choose the correct ReleasePlan name for your release type
- Ensure template content and ReleasePlan match the intended release maturity level

**Release Types:**
- **RHEA** (default): Enhancement Advisory - standard feature releases
- **RHSA**: Security Advisory - requires `--cves-file` parameter
  - CVE file format: One CVE per line (CVE-YYYY-NNNNN)
  - Comments starting with # are ignored
  - Empty lines are skipped

**Example Templates:**

Create different templates based on release maturity and type:
- `release-notes-ga-rhea.yaml` - GA enhancement advisory
- `release-notes-ga-rhsa.yaml` - GA security advisory
- `release-notes-tp-rhea.yaml` - Tech Preview enhancement advisory
- `release-notes-tp-rhsa.yaml` - Tech Preview security advisory

**Note:** The template content (synopsis, description, topic) should reflect whether the release is GA or Tech Preview. The `--release-type` parameter controls whether it's an RHEA or RHSA.

## Naming Conventions

### Release Names

Pattern: `<component>-<version>-<env>-<seq>`

**Example:** `my-component-1-2-0-prod-1`

Components:
- `my-component`: Component name
- `1-2-0`: Version (dots replaced with dashes)
- `prod`: Environment (stage/prod)
- `1`: Sequence number

### ReleasePlan Names

Common pattern: `<app-name>-<env>[-<version>]`

**Examples:**
- Stage: `app-stage` or `app-stage-1-0`
- Prod: `app-prod` or `app-prod-1-0`

## Querying Releases

Use the **kubernetes skill** for all kubectl operations.

**Key Konflux-specific label:**
- Find releases by commit SHA: `pac.test.appstudio.openshift.io/sha=<full-40-char-sha>`

**Useful fields:**
- Component: `.metadata.labels["appstudio.openshift.io/component"]`
- Snapshot: `.spec.snapshot`
- ReleasePlan: `.spec.releasePlan`
- Status: `.status.conditions[type=Released].status`
- Image URLs: `.status.artifacts.images[].urls[]`

## Common Patterns

### Multi-Component Release

For applications with multiple components:

1. Resolve tag to SHA (once)
2. Query all stage releases with that SHA
3. Filter to successful releases only
4. For each successful stage release:
   - Extract component name and snapshot from stage release
   - Determine accelerator/variant type from component name
   - Generate unique production release name
   - **User determines release maturity (GA or TP)**
   - Select appropriate template file based on maturity
   - Select appropriate ReleasePlan name based on maturity
   - Run script with all required parameters
   - Generate prod YAML
5. Create output directory with all YAMLs
6. Generate summary document

**Parameter Coordination:**
The user must ensure these parameters align for the intended release:
- **For GA releases:**
  - Template: `ga-rhea.yaml` (or `ga-rhsa.yaml` for security)
  - ReleasePlan: `my-product-ga-prod` (GA production plan)
  - Release name should reflect GA maturity if needed
- **For Tech Preview releases:**
  - Template: `tp-rhea.yaml` (or `tp-rhsa.yaml` for security)
  - ReleasePlan: `my-product-tp-prod` (TP production plan)
  - Release name should reflect TP maturity if needed
- Use `--release-type RHEA` for enhancements, `--release-type RHSA` for security
- Templates can be stored in a central location or per-component

**Example directory structure:**
```
out/
├── component-1-prod.yaml
├── component-2-prod.yaml
├── component-3-prod.yaml
└── RELEASE_SUMMARY.md
```

### Release Summary Document

Include in summary:
- Release date
- Git commit SHA and URL
- Component status table
- Stage release information
- Generated YAML filenames
- Deployment instructions
- Verification steps

### Component Filtering

Support optional component filtering by accelerator type:

**User provides:** `cuda,rocm,cpu` (accelerator types to include)

**Workflow:**
1. Query all stage releases by SHA
2. Extract component names from labels
3. Match against accelerator patterns in component names
4. Generate YAMLs only for matched components

**Component extraction:**
```
Label: appstudio.openshift.io/component = "my-component-cuda-ubi9"
Extract accelerator type from component name (e.g., "cuda")
```

## Error Handling

**Tag not found:**
- Verify tag exists in GitLab
- Check tag name capitalization
- Try using commit SHA directly

**No stage releases found:**
- Verify SHA is correct (full 40 characters)
- Check if stage releases have completed
- Verify namespace is correct

**Stage release failed:**
- Check PipelineRun logs
- Do NOT create production releases for failed components
- Report failure to user
- Continue with successful releases only

**Template file not found:**
- Verify template file path is correct
- Check file exists and is readable
- Ensure template is valid YAML

**Template parsing error:**
- Validate YAML syntax in template
- Check for proper indentation
- Ensure all fields are properly quoted if needed

**CVE file not found:**
- Verify file path is correct
- Check file format (one CVE per line)
- Ensure CVEs are in CVE-YYYY-NNNNN format

## Integration with Other Skills

**gitlab skill:**
- Resolve tags to commit SHAs
- Get commit details and metadata

**kubernetes skill:**
- Query releases with label selectors
- Extract release status and fields
- Monitor release progress

**konflux skill (this):**
- Understand release concepts
- Generate release YAMLs
- Orchestrate multi-component releases

## Best Practices

**Always use full SHAs:**
- Label selectors require full 40-character SHAs
- Short SHAs won't match labels

**Verify before generating:**
- All stage releases must succeed
- Snapshots must be captured
- Production ReleasePlans must exist for both GA and TP (if releasing both)

**Coordinate parameters correctly:**
- **GA releases require:** GA template + GA ReleasePlan name
- **TP releases require:** TP template + TP ReleasePlan name
- The script has no awareness of release type - you control this via parameter selection
- Double-check template and ReleasePlan match before generating

**Use release notes templates:**
- Store template files in version control
- Create separate templates for GA vs Tech Preview releases
- Create separate templates for RHEA vs RHSA if content differs
- Use `{version}` and `{accelerator}` placeholders for dynamic content
- Test templates before using in production

**Understand release types:**
- Use RHEA for feature/enhancement releases (via `--release-type RHEA`)
- Use RHSA for security updates with CVE list (via `--release-type RHSA`)
- Provide CVE file in correct format for RHSA
- The `type` field in template can be overridden by `--release-type` argument

**Generate summaries:**
- Document what was released
- Include verification steps

## Dependencies

**Required:**
- `kubectl` - Kubernetes operations (via kubernetes skill)
- `jq` - JSON parsing
- `python3` - For YAML generation script (Python 3.6+)
- `PyYAML` - Python YAML library

**Optional:**
- `glab` - GitLab operations (via gitlab skill)

**Script Scope:**
- The `generate_release_yaml.py` script is generic and product-agnostic
- Product-specific release notes are defined in template files
- Each product can maintain their own template files
- Templates use `{version}` and `{accelerator}` for dynamic substitution
