---
name: konflux-release
description: Create production releases on the Konflux platform. Handles the complete stage-to-production release workflow including discovering stage releases, generating production release YAMLs with release notes, and preparing them for review. Supports manual mode and config-driven mode with an external product config directory.
allowed-tools: Bash(*/konflux-release/scripts/generate_release_yaml.py *),Bash(kubectl get *),Bash(skopeo inspect *),Bash(glab api --method GET *),Write(*RELEASE_SUMMARY*),Bash(sed *upload-rhel-ai-disk-image-pipelinerun.yaml*)
---

# Konflux Release

## Overview

Konflux is an open source build and release platform based on OpenShift and Tekton. This skill handles the stage-to-production release workflow: discovering stage releases by commit SHA, generating production release YAMLs with release notes, and preparing them for human review.

The skill generates release YAML files and a summary document. It does NOT apply releases to the cluster -- application of release YAMLs is handled separately through manual review or CI pipelines.

The skill operates in two modes:

- **Manual mode** - provide all parameters directly (namespace, release plans, templates, etc.). Output files are written to a local directory.
- **Config-driven mode** - read product configuration from an external config directory added as a working directory. When a product configs repo is present, its CLAUDE.md provides all product-specific context including where to find component definitions, release plans, release notes templates, and where to store outputs.

**Prerequisites:** `kubectl`, `python3`, `jq`, and optionally `glab` and `skopeo`. These are expected to be pre-installed. Do NOT check or install dependencies upfront — just run the commands and scripts directly. If something fails due to a missing dependency, then install it using the scripts in `tools/`.

**Scripts:**
This skill includes helper scripts in `scripts/` directory.

## Core Concepts

- **Release** - a deployment of a specific snapshot to an environment
- **Snapshot** - a point-in-time reference to built container images
- **ReleasePlan** - defines how and where releases are deployed
- **Application** - group of related components
- **Component** - individual buildable/deployable unit
- **Stage-RC Release** - a release candidate deployed to a staging registry for validation before production. Follows the same workflow as production but uses stage-rc release plans

## Script Execution Requirements

1. **Single-line commands only** - NO line breaks or backslash continuations
2. **DO NOT change directory** - execute scripts using their full absolute path
3. **Full path required** - the script must be invoked with its full filesystem path, not a relative path
4. **One tool call per component** - each component must be handled with a separate tool call. Do NOT use shell loops (`for`, `while`), background processes (`&`), or subshells to batch multiple components into a single command

**Correct execution:**
```bash
/full/path/to/konflux-release/scripts/generate_release_yaml.py --version 1.0 --snapshot bar --release-plan prod --release-name foo-1-0-prod-1 --accelerator Variant --namespace ns --release-notes-template /path/to/template.yaml --release-type RHEA --output /path/to/out/foo-prod-1.yaml
```

**Incorrect execution:**
```bash
# DON'T - relative path (won't resolve)
scripts/generate_release_yaml.py ...

# DON'T - changing directory first
cd scripts && ./generate_release_yaml.py ...

# DON'T - line breaks
/path/to/generate_release_yaml.py \
  --component foo \
  --version 1.0

# DON'T - shell loops or background processes
for comp in foo bar baz; do /path/to/generate_release_yaml.py --component $comp ...; done
/path/to/generate_release_yaml.py --component foo ... &
/path/to/generate_release_yaml.py --component bar ... &
wait
```

**Permission pattern:**
- `*/konflux-release/scripts/generate_release_yaml.py *`

This pattern matches the script in any user directory or plugin cache location.

## Release Workflow

### Stage-to-Production Pattern

```
1. Code merged -> CI builds -> Stage Release created
2. Stage Release succeeds -> Snapshot captured (references built images)
3. Production Release YAML generated -> References same Snapshot (same images)
4. Release YAMLs reviewed and applied (manually or via CI)
```

Key principle: stage and production releases reference the same Snapshot because it points to the same built container images.

The same workflow applies to **stage-RC releases**: they use stage-rc release plans instead of production plans, targeting a staging registry for release candidate validation before production.

### Step 1: Resolve Input to Commit SHA

Three options depending on what the user provides:

**Option A - Direct SHA:** User already has the full 40-character commit SHA. No resolution needed.

**Option B - Git tag via glab:**
```bash
glab api --method GET "projects/<url-encoded-project>/repository/commits/<tag>" | jq -r '.id'
```

**Option C - Image URL via skopeo:** Extract the commit SHA from container image labels:
```bash
skopeo inspect --no-tags docker://<image-url> | jq -r '.Labels["vcs-ref"]'
```

### Step 2: Find Stage Releases by SHA

Query releases using the commit SHA label:
```bash
kubectl get releases -n <namespace> -l "pac.test.appstudio.openshift.io/sha=<full-40-char-sha>"
```

Use the full 40-character SHA. Short SHAs won't match labels.

### Step 3: Detect Versioned vs Non-Versioned Releases

Check the `appstudio.openshift.io/application` label on the releases to determine the application name. Some applications use versioned release plans (with version suffix) while others use a single unversioned plan.

```bash
kubectl get releases -n <namespace> -l "pac.test.appstudio.openshift.io/sha=<sha>" -o jsonpath='{.items[0].metadata.labels.appstudio\.openshift\.io/application}'
```

### Step 4: Filter to Successful Releases

Check that each stage release has completed successfully:

```bash
kubectl get releases -n <namespace> -l "pac.test.appstudio.openshift.io/sha=<sha>" -o json | jq '[.items[] | select(.status.conditions[]? | select(.type == "Released" and .status == "True")) | {name: .metadata.name, component: .metadata.labels["appstudio.openshift.io/component"], snapshot: .spec.snapshot, releasePlan: .spec.releasePlan}]'
```

- Only proceed with releases where `.status.conditions[type=Released].status = "True"`
- Report any failed releases to the user
- Do NOT generate production YAMLs for failed stage releases

**Application alignment:** All stage releases in a batch must belong to the same Konflux application. Check the `appstudio.openshift.io/application` label on each release. If a component's stage release belongs to a different application, do not include it — flag it to the user. Never mix components from different applications in the same release batch.

### Step 5: Determine Component Properties

For each successful stage release, extract:

- **Component name:** `.metadata.labels["appstudio.openshift.io/component"]`
- **Snapshot name:** `.spec.snapshot`
- **Stage ReleasePlan:** `.spec.releasePlan`

**Component names must come from the cluster.** Always use the actual Konflux component name from the `appstudio.openshift.io/component` label — never construct or guess component names. Konflux components use **branch-based** suffixes (e.g., `-3-3` for branch `3.3`), not release version suffixes (e.g., `-3-3-1` for version `3.3.1`). Z-stream releases like `3.3.1` reuse the same components as `3.3.0`.

Then determine:

- **Tech preview status** - from product config or user input
- **Production ReleasePlan name** - derive from stage plan naming convention
- **Release notes template** - select appropriate template based on component type and tech preview status
- **Variant/accelerator display name** - derive from component name

### Step 5b: Extract Stage Image URLs

After identifying successful stage releases, extract the timestamped image URL from each release's artifacts:

```bash
kubectl get release <stage-release-name> -n <namespace> -o json | jq -r '.status.artifacts.images[] | select(.name == "<component>") | .urls[] | select(test("-[0-9]+$"))'
```

The filter `test("-[0-9]+$")` selects the URL whose tag ends with the numeric build timestamp, distinguishing it from `-source`, version-only, and digest tags. Include this URL in the release summary so reviewers can verify the exact image being promoted.

### Step 6: Auto-Increment Release Sequence

Determine the next sequence number by counting existing releases whose name starts with the same prefix (base-component + version + release-type):

```bash
kubectl get releases -n <namespace> -o json | jq '[.items[] | select(.metadata.name | startswith("<base-component>-<version-dashed>-<release-type>-"))] | length'
```

Use length + 1 as the next sequence number.

For full-application releases, count by release plan instead:

```bash
kubectl get releases -n <namespace> -o json | jq '[.items[] | select(.spec.releasePlan == "<release-plan>")] | length'
```

### Step 7: Generate Production Release YAMLs

The script automatically creates the output directory. Use the provided script for each component (full path, single line):

```bash
/full/path/to/konflux-release/scripts/generate_release_yaml.py --version <version> --snapshot <snapshot-name> --release-plan <prod-release-plan> --release-name <release-name> --accelerator <accelerator> --namespace <namespace> --release-notes-template <template-path> --release-type <RHEA|RHSA> --output /path/to/output/<component>-prod-<seq>.yaml
```

**Required parameters:**
- `--version` - semantic version
- `--snapshot` - snapshot name from the successful stage release
- `--release-plan` - production release plan name
- `--release-name` - unique release name (see naming conventions)
- `--accelerator` - variant/accelerator type for template substitution
- `--namespace` - Kubernetes namespace
- `--release-notes-template` - path to release notes YAML template
- `--release-type` - RHEA (default) or RHSA
- `--output` - output file path (must include sequence number — see Output File Naming below)

**RHSA parameters (required when `--release-type RHSA`):**
- `--cves-file` - path to CVE list file
- `--component` - single actual Konflux component name for CVE entries, OR
- `--cve-components` - comma-separated list of actual Konflux component names (for full-application releases with multiple components per Release CR)

**Optional parameters:**
- `--grace-period` - grace period in days (default: 30)

### Step 7b: Generate Cloud Image Upload PipelineRuns

When releasing disk image components for rhelai, also generate PipelineRun YAMLs for uploading cloud disk images. The following component-to-cloud mappings are supported:

| Component pattern | Accelerator | Cloud Provider |
|---|---|---|
| `bootc-cuda-aws-disk-image` | cuda | aws |
| `bootc-cuda-azure-disk-image` | cuda | azure |
| `bootc-rocm-azure-disk-image` | rocm | azure |

**When to generate:** During both full releases and single-component releases, if the release includes any of the above cloud disk image components.

**How to generate:** Use the PipelineRun YAML template at `templates/upload-rhel-ai-disk-image-pipelinerun.yaml` and substitute the placeholder variables using `sed`:

```bash
sed -e 's/{{ACCELERATOR}}/cuda/g' -e 's/{{CLOUD_PROVIDER}}/aws/g' -e 's|{{CONTAINER_IMAGE}}|<image-ref>|g' -e 's/{{PULL_SECRET_NAME}}/<pull-secret>/g' -e 's/{{RHEL_AI_VERSION}}/<version>/g' -e 's/{{NAMESPACE}}/<namespace>/g' /full/path/to/konflux-release/templates/upload-rhel-ai-disk-image-pipelinerun.yaml > /path/to/output/upload-rhel-ai-cuda-aws-disk-image.yaml
```

**Variable sources:**

| Variable | Source |
|---|---|
| `ACCELERATOR` | Parsed from the component name (e.g., `bootc-cuda-aws-disk-image` → `cuda`) |
| `CLOUD_PROVIDER` | Parsed from the component name (e.g., `bootc-cuda-aws-disk-image` → `aws`) |
| `CONTAINER_IMAGE` | Digest-pinned OCI reference from the release snapshot (e.g., `quay.io/...@sha256:...`). Must include the `@sha256:` digest, not a tag. Extract via: `kubectl get snapshot <name> -n <ns> -o json \| jq -r '.spec.components[] \| select(.name == "<component>") \| .containerImage'` |
| `PULL_SECRET_NAME` | From `config-disk-images.yaml` or derived from application/branch (e.g., `rhelai-bootc-3-3-pull`) |
| `RHEL_AI_VERSION` | The release version provided by the user (e.g., `3.3.0`) |
| `NAMESPACE` | From `config-disk-images.yaml` field `definitions[].tenant` (e.g., `rhel-ai-tenant`) |

**Output files:** One PipelineRun YAML per cloud disk image component, named `upload-rhel-ai-<accelerator>-<cloud>-disk-image.yaml`. These files are written to the same release version directory as the Release CRs (e.g., `rhelai/<branch>/releases/<version>/`).

### Step 8: Generate Release Summary

Create a summary document that includes:
- Release date and release type (production, stage-rc, etc.)
- Git commit SHA and source URL
- Component table with: component name, type (GA/TP), release name, release plan, stage image URL (from Step 5b), snapshot, and stage release
- Generated YAML filenames
- Links to Konflux UI for monitoring (if available)

### Step 9: Deliver for Review

The generated release YAMLs and summary are NOT applied directly to the cluster.

**Config-driven mode:** Follow the config repo's CLAUDE.md instructions for where to store output files. Commit the generated files and open a merge request against the config repo for human review.

**Manual mode:** Write the files to a local output directory. The user decides how to apply them (manually, via CI, etc.).

## Config-Driven Mode

When a product configs repository is added as a working directory, the skill can read product configuration automatically instead of requiring all parameters manually.

### How It Works

1. Claude reads the configs repo's CLAUDE.md to discover product-specific context
2. The CLAUDE.md in that repo provides all necessary details: directory structure, config file format, release notes locations, output conventions, and any product-specific instructions
3. Follow the conventions documented there for storing generated files and creating merge requests

### What to Expect From the Config Repo

The config repo's CLAUDE.md should document:
- Where product config files are and what fields are relevant for releases
- Where release notes templates are stored and how to select the right one
- Where to write generated release YAMLs and summaries
- Any product-specific conventions or naming patterns
- Konflux UI URLs for constructing monitoring links

The skill does not assume any particular config file structure -- it relies entirely on the config repo's CLAUDE.md for guidance.

## Release Notes Templates

### Template Format

```yaml
synopsis: "Product Name {version} ({accelerator})"
description: "Product Name"
topic: "Product Name {version} ({accelerator}) is now available."
references:
  - https://example.com/product
solution: ""
```

### Template Variables

- `{version}` - provided via `--version` argument
- `{accelerator}` - provided via `--accelerator` argument

The script replaces all placeholders recursively through all string values.

### Template Selection

- **GA components** - use `ga.yaml` template + GA production release plan
- **Tech preview components** - use `tech-preview.yaml` template + tech preview production release plan
- **Special variants** - if a variant-specific template exists (e.g., `special-variant.yaml`), use it instead of the default GA/TP template

### Release Types

- **RHEA** (default) - Enhancement Advisory, standard feature releases
- **RHSA** - Security Advisory, requires `--cves-file` and either `--component` (single) or `--cve-components` (multiple)
  - **CVE component names must be actual Konflux component names** from the snapshot — never construct or guess them. Query the snapshot to get the real component names (see "RHSA Component Names" below)
  - CVE file format: one CVE per line (CVE-YYYY-NNNNN)
  - Comments starting with # are ignored
  - Empty lines are skipped

#### RHSA Component Names

For RHSA releases, each CVE entry requires a `component` field. This must be the **actual Konflux component name** as it exists in the cluster — the same name that appears in the `appstudio.openshift.io/component` label on releases and in the snapshot's component list.

**How to get real component names from a snapshot:**
```bash
kubectl get snapshot <snapshot-name> -n <namespace> -o json | jq -r '.spec.components[].name'
```

**For single-component releases:** pass the Konflux component name directly as `--component` (e.g., `--component rhaiis-cuda-ubi9-3-4`).

**For full-application releases (e.g., rhelai):** the snapshot contains many components. Each CVE must be paired with each affected component. Extract all component names from the snapshot and pass them as a comma-separated list to `--cve-components` (e.g., `--cve-components bootc-cuda-3-3,bootc-rocm-3-3,bootc-cuda-aws-3-3`). This generates one CVE entry per CVE × component combination.

**Common mistake:** do NOT construct component names by appending the release version (e.g., `bootc-cuda-3-3-1`). Konflux components use branch-based suffixes (`-3-3`), not release version suffixes (`-3-3-1`). A z-stream release like `3.3.1` uses the same `-3-3` components as `3.3.0`.

## Release Summary

### Structure

`RELEASE_SUMMARY.md` is organised into **one section per release type** (production, stage-rc, etc.). Each section is appended when that type of release is created. Never mix release types in a single table.

```markdown
# Release Summary

## Production Release (YYYY-MM-DD)

### Components

| Component | Type | Release Name | Release Plan | Stage Image | Snapshot | Stage Release |
|-----------|------|--------------|--------------|-------------|----------|---------------|
| component-1 | GA | name-prod-1 | plan-prod | quay.io/org/img:tag-ts | snap-name | stage-rel-name |
| component-2 | TP | name-tp-prod-1 | plan-tp-prod | quay.io/org/img:tag-ts | snap-name | stage-rel-name |

### Commit SHA

| Field | Value |
|-------|-------|
| SHA | abc123... |
| Source | <repository-url> |

### Generated Files
- component-1-prod-1.yaml
- component-2-prod-1.yaml
```

- **Stage Image** — the timestamped image URL extracted from `.status.artifacts.images[].urls[]` (see Step 5b)
- **Snapshot** and **Stage Release** — linked to Konflux UI if available
- Each release type (prod, stage-rc) gets its own heading and table

### Storage

In config-driven mode, follow the config repo's CLAUDE.md for where to store the summary.

In manual mode, store it alongside the generated YAMLs in the output directory.

## Konflux UI Links

When a Konflux UI base URL is available (provided by the config repo or user), construct monitoring links using these patterns:

- **Prefix:** `<base-url>/ns/<tenant>/applications/<application>`
- **Releases list:** `<prefix>/releases`
- **Snapshot:** `<prefix>/snapshots/<snapshot-name>`
- **Release:** `<prefix>/releases/<release-name>`

Include these links in the release summary and any merge request description to help reviewers verify the release.

## Naming Conventions

### Release Names

**Single-component releases** (one Release CR per component — the default):

Pattern: `<base-component>-<version-dashed>-<release-type>-<seq>`

Example: `my-comp-cuda-1-2-0-prod-1`, `my-comp-rocm-1-2-0-stage-rc-1`

- `<base-component>` - component name from the product config (without branch/version suffixes that Konflux appends to the Konflux component name)
- `<version-dashed>` - semantic release version with dots replaced by dashes (e.g., `3.3.1` → `3-3-1`, `3.4.0-ea.2` → `3-4-0-ea-2`)
- `<release-type>` - release type suffix (e.g., `prod`, `stage-rc`)
- `<seq>` - sequence number (auto-incremented per base-component + release-type, starting from 1)

This makes it possible to identify which component/variant was released without opening the Release CR. Do NOT use the full Konflux component name (which includes branch version suffixes) — that causes version duplication in the release name. Keep names under 63 characters (Kubernetes limit).

**Full-application releases** (one Release CR covers all components in a snapshot):

Pattern: `<release-plan-name>-<seq>`

- `<release-plan-name>` - the target release plan name
- `<seq>` - sequence number (auto-incremented per release plan, starting from 1)

### Output File Naming

Output YAML filenames MUST include the sequence number to prevent overwriting previous releases:

Pattern: `<base-component>-<release-type>-<seq>.yaml`

Examples: `my-comp-cuda-prod-1.yaml`, `my-comp-cuda-stage-rc-2.yaml`

**Never overwrite existing release files.** Each Release CR YAML is an immutable record of a release. When generating a new release for a component that already has release files, always create a new file with the next sequence number — never reuse or overwrite an existing filename.

### ReleasePlan Types

There are four types of release plans. The skill **creates** Release CRs targeting prod, tech-preview-prod, or stage-rc plans. It **reads** stage releases (created automatically by CI) to discover snapshots.

| Type | Pattern | Purpose | Created by |
|------|---------|---------|------------|
| Stage | `<app>-stage` | Automatic nightly/development builds | CI (on push) — skill only reads these |
| Stage-RC | `<app>-stage-rc` | Release candidate validation on staging registry | Skill (manual trigger) |
| GA production | `<app>-prod` | GA production release | Skill (manual trigger) |
| TP production | `<app>-tech-preview-prod` | Tech preview production release | Skill (manual trigger) |

**Which plan to use when creating a Release CR:**
- User asks for a **production release** → use `*-prod` (GA components) or `*-tech-preview-prod` (tech preview components)
- User asks for a **stage-rc release** → use `*-stage-rc`
- Never create Release CRs targeting `*-stage` — those are automatic

## Multi-Component Release

For applications with multiple components:

1. Resolve tag/image to SHA (once)
2. Query all stage releases with that SHA
3. Filter to successful releases only
4. For each successful stage release, make a **separate tool call** (no loops or backgrounding):
   - Extract component name and snapshot
   - Determine variant from component name
   - Check if tech preview (from config or user input)
   - Select appropriate release plan and template
   - Auto-increment release sequence number
   - Generate production release YAML via individual script invocation
5. Create output directory with all YAMLs
6. Generate release summary document
7. Commit and open MR for review (config-driven) or deliver locally (manual)

### Component Filtering

Support optional filtering by variant/accelerator type:

User provides a list of types to include.

1. Query all stage releases by SHA
2. Extract component names from labels
3. Match against variant patterns in component names
4. Generate YAMLs only for matched components

## Error Handling

**Tag not found:**
- Verify tag exists in the source repository
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

**Release name already exists:**
- Auto-increment the sequence number
- Query existing releases to find the next available number

**Config repo not available:**
- Fall back to manual mode
- Ask the user for all required parameters directly

## Dependencies

Do NOT proactively check or install dependencies. Run commands and scripts directly. Only use these install scripts if a command fails due to a missing tool.

**Required:** `kubectl`, `jq`, `python3`, `PyYAML`

**Optional:** `glab` (tag resolution), `skopeo` (image inspection)

**Install scripts (use only if needed):**
```bash
tools/jq/install.sh              # jq
tools/kubectl/install.sh         # kubectl
tools/skopeo/install.sh          # skopeo
tools/glab/install.sh            # glab
# PyYAML is installed via pip (tools/python/konflux-release-requirements.txt)
```

## Best Practices

**Always use full SHAs** - label selectors require full 40-character SHAs. Short SHAs won't match.

**Verify before generating** - all stage releases must succeed and snapshots must be captured before generating production YAMLs.

**Coordinate parameters correctly:**
- GA releases require: GA template + GA ReleasePlan name
- Tech preview releases require: TP template + TP ReleasePlan name
- The script has no awareness of release type - you control this via parameter selection

**Use release notes templates** - store templates in version control, use `{version}` and `{accelerator}` placeholders for dynamic content.

**Generate summaries** - document what was released, include verification steps and links.

**Review before applying** - generated files should always go through human review before being applied to the cluster.
