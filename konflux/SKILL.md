---
name: konflux
description: Query and manage Konflux/Tekton pipeline resources (pipelinerun, taskrun, pipeline, task) and GitOps resources (release, application, component) using efficient kubectl+jq patterns. Includes RHEL AI release workflow automation and YAML generation tools. Avoids MCP context pollution.
---

# Kubernetes Pipeline & GitOps Resources Query

Query Tekton pipeline resources and GitOps resources (application, component, release) using kubectl.

## Target Resources

**Tekton Resources:**
- `pipelinerun` - Pipeline execution instances
- `pipeline` - Pipeline definitions
- `taskrun` - Task execution instances
- `task` - Task definitions

**GitOps/AppStudio Resources:**
- `application` - Application definitions
- `component` - Component definitions
- `release` - Release definitions

## Instructions

When this skill is invoked:

1. Determine which resource(s) the user wants to query
2. Use kubectl via Bash tool to fetch resources
3. Parse JSON/YAML output and present in readable format
4. Highlight important information: status, errors, timestamps
5. If no specific resource is mentioned, provide a summary of all resource types

## Common Query Patterns

### List All PipelineRuns

```bash
kubectl get pipelineruns -A -o json | jq -r '
  ["NAMESPACE", "NAME", "STATUS", "STARTED", "COMPLETED"],
  (.items[] | [
    .metadata.namespace,
    .metadata.name,
    (.status.conditions[]? | select(.type=="Succeeded") | .status // "Unknown"),
    (.status.startTime // "N/A"),
    (.status.completionTime // "Running")
  ]) | @tsv' | column -t -s $'\t'
```

### List Failed PipelineRuns

```bash
kubectl get pipelineruns -A -o json | jq -r '
  .items[] |
  select(.status.conditions[]? | select(.type=="Succeeded" and .status=="False")) |
  {
    namespace: .metadata.namespace,
    name: .metadata.name,
    reason: .status.conditions[0].reason,
    message: .status.conditions[0].message,
    started: .status.startTime
  }'
```

### List Running PipelineRuns

```bash
kubectl get pipelineruns -A -o json | jq -r '
  .items[] |
  select(.status.completionTime == null) |
  [
    .metadata.namespace,
    .metadata.name,
    .status.startTime,
    (.status.conditions[]? | select(.type=="Succeeded") | .reason // "Running")
  ] | @tsv' | column -t -s $'\t'
```

### Get Specific PipelineRun Details

```bash
kubectl get pipelinerun <name> -n <namespace> -o yaml
```

### List All TaskRuns

```bash
kubectl get taskruns -A -o json | jq -r '
  ["NAMESPACE", "NAME", "STATUS", "STARTED", "COMPLETED"],
  (.items[] | [
    .metadata.namespace,
    .metadata.name,
    (.status.conditions[]? | select(.type=="Succeeded") | .status // "Unknown"),
    (.status.startTime // "N/A"),
    (.status.completionTime // "Running")
  ]) | @tsv' | column -t -s $'\t'
```

### List Failed TaskRuns

```bash
kubectl get taskruns -A -o json | jq -r '
  .items[] |
  select(.status.conditions[]? | select(.type=="Succeeded" and .status=="False")) |
  {
    namespace: .metadata.namespace,
    name: .metadata.name,
    reason: .status.conditions[0].reason,
    message: .status.conditions[0].message
  }'
```

### List Pipelines

```bash
kubectl get pipelines -A -o json | jq -r '
  ["NAMESPACE", "NAME", "CREATED"],
  (.items[] | [
    .metadata.namespace,
    .metadata.name,
    .metadata.creationTimestamp
  ]) | @tsv' | column -t -s $'\t'
```

### List Tasks

```bash
kubectl get tasks -A -o json | jq -r '
  ["NAMESPACE", "NAME", "CREATED"],
  (.items[] | [
    .metadata.namespace,
    .metadata.name,
    .metadata.creationTimestamp
  ]) | @tsv' | column -t -s $'\t'
```

### List Applications

```bash
kubectl get applications -A -o json | jq -r '
  ["NAMESPACE", "NAME", "DISPLAY_NAME", "CREATED"],
  (.items[] | [
    .metadata.namespace,
    .metadata.name,
    (.spec.displayName // .metadata.name),
    .metadata.creationTimestamp
  ]) | @tsv' | column -t -s $'\t'
```

### Get Application Details

```bash
kubectl get application <name> -n <namespace> -o yaml
```

### List Components

```bash
kubectl get components -A -o json | jq -r '
  ["NAMESPACE", "NAME", "APPLICATION", "CREATED"],
  (.items[] | [
    .metadata.namespace,
    .metadata.name,
    (.spec.application // "N/A"),
    .metadata.creationTimestamp
  ]) | @tsv' | column -t -s $'\t'
```

### Get Component Details

```bash
kubectl get component <name> -n <namespace> -o yaml
```

### List Releases

```bash
kubectl get releases -A -o json | jq -r '
  ["NAMESPACE", "NAME", "APPLICATION", "CREATED"],
  (.items[] | [
    .metadata.namespace,
    .metadata.name,
    (.spec.application // "N/A"),
    .metadata.creationTimestamp
  ]) | @tsv' | column -t -s $'\t'
```

### Get Release Details

```bash
kubectl get release <name> -n <namespace> -o yaml
```

### Find Release by Commit SHA and Component

Find a specific release by filtering on commit SHA and component name:

```bash
kubectl get releases -n <namespace> -l "pac.test.appstudio.openshift.io/sha=<full-40-char-sha>" -o json | \
  jq '.items[] | select(.metadata.labels["appstudio.openshift.io/component"] == "<component-name>")'
```

**Example**:
```bash
kubectl get releases -n rhel-ai-tenant -l "pac.test.appstudio.openshift.io/sha=239f91eb6a231296b81860443ec0c5580905f7a9" -o json | \
  jq '.items[] | select(.metadata.labels["appstudio.openshift.io/component"] == "bootc-cuda")'
```

### Extract Release Details

Extract comprehensive release information for verification:

```bash
kubectl get releases -n <namespace> -l "pac.test.appstudio.openshift.io/sha=<full-sha>" -o json | \
  jq -r '.items[] | select(.metadata.labels["appstudio.openshift.io/component"] == "<component>") | {
    name: .metadata.name,
    component: .metadata.labels["appstudio.openshift.io/component"],
    application: .metadata.labels["appstudio.openshift.io/application"],
    snapshot: .spec.snapshot,
    releasePlan: .spec.releasePlan,
    status: (.status.conditions[]? | select(.type=="Released") | .status),
    pipelineUrl: .metadata.annotations["pac.test.appstudio.openshift.io/log-url"],
    commitSha: .metadata.annotations["pac.test.appstudio.openshift.io/sha"],
    commitUrl: .metadata.annotations["pac.test.appstudio.openshift.io/sha-url"],
    imageUrls: [.status.artifacts.images[]?.urls[]?]
  }'
```

### Check Release Status (Succeeded/Failed)

Filter releases that have succeeded:

```bash
kubectl get releases -n <namespace> -l "pac.test.appstudio.openshift.io/sha=<full-sha>" -o json | \
  jq -r '.items[] |
    select(.metadata.labels["appstudio.openshift.io/component"] == "<component>") |
    select(.status.conditions[]? | select(.type=="Released" and .status=="True"))'
```

Filter releases that have failed:

```bash
kubectl get releases -n <namespace> -o json | \
  jq -r '.items[] |
    select(.status.conditions[]? | select(.type=="Released" and .status=="False")) |
    {
      name: .metadata.name,
      component: .metadata.labels["appstudio.openshift.io/component"],
      reason: (.status.conditions[] | select(.type=="Released") | .reason),
      message: (.status.conditions[] | select(.type=="Released") | .message)
    }'
```

### Extract Image URLs from Release

Extract timestamped image URLs from release artifacts:

```bash
kubectl get release <release-name> -n <namespace> -o json | \
  jq -r '.status.artifacts.images[]?.urls[]?'
```

Extract timestamped version from image URL:

```bash
kubectl get release <release-name> -n <namespace> -o json | \
  jq -r '.status.artifacts.images[]?.urls[]? | select(contains("@sha256")) |
    capture(".*:(?<version>[0-9.]+-[0-9]+)@sha256.*") | .version'
```

### Verify Release Matches Criteria

Comprehensive verification query that checks all criteria:

```bash
kubectl get releases -n <namespace> -l "pac.test.appstudio.openshift.io/sha=<full-sha>" -o json | \
  jq --arg component "<component-name>" --arg sha "<full-sha>" '
    .items[] |
    select(.metadata.labels["appstudio.openshift.io/component"] == $component) |
    select(.metadata.annotations["pac.test.appstudio.openshift.io/sha"] == $sha) |
    select(.status.conditions[]? | select(.type=="Released" and .status=="True")) |
    {
      valid: true,
      name: .metadata.name,
      component: .metadata.labels["appstudio.openshift.io/component"],
      snapshot: .spec.snapshot,
      releasePlan: .spec.releasePlan,
      application: .metadata.labels["appstudio.openshift.io/application"]
    }
  '
```

If the query returns empty, the release does not exist or does not match all criteria.

### Batch Query Multiple Releases by SHA

Query multiple components efficiently by iterating over commit SHAs:

```bash
# Define arrays
components=("bootc-cuda" "bootc-rocm" "bootc-cpu")
shas=("239f91eb6a231296b81860443ec0c5580905f7a9" "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8g9h0" "...")

# Query each combination
for i in "${!components[@]}"; do
  component="${components[$i]}"
  sha="${shas[$i]}"

  echo "Querying ${component} @ ${sha:0:7}..."
  kubectl get releases -n rhel-ai-tenant -l "pac.test.appstudio.openshift.io/sha=${sha}" -o json | \
    jq --arg comp "$component" '.items[] | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)'
done
```

### Generate Release Resource YAML from Stage Release

Use the `scripts/generate-release-yaml.sh` script (located in this skill's scripts directory) to automatically query stage releases and generate production release YAML:

```bash
# Get the skill directory path
SKILL_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Run the script from skill directory
"${SKILL_DIR}/scripts/generate-release-yaml.sh" \
  --component bootc-cuda \
  --sha 239f91eb6a231296b81860443ec0c5580905f7a9 \
  --version 3.0.0 \
  --env prod \
  --rpa bootc-containers \
  --output /workspace/out/bootc-cuda-release.yaml
```

Or invoke directly with a relative path:
```bash
.claude/skills/konflux/scripts/generate-release-yaml.sh \
  --component bootc-cuda \
  --sha 239f91eb6a231296b81860443ec0c5580905f7a9 \
  --version 3.0.0 \
  --env prod \
  --rpa bootc-containers \
  --output /workspace/out/bootc-cuda-release.yaml
```

**Script features**:
- Queries stage release by SHA and component
- Verifies release succeeded
- Extracts snapshot name automatically
- Generates properly formatted release YAML
- Validates all inputs (SHA length, environment, etc.)

**Manual usage** (if script not available):
```bash
# Query stage release
RELEASE_DATA=$(kubectl get releases -n rhel-ai-tenant \
  -l "pac.test.appstudio.openshift.io/sha=${SHA}" -o json | \
  jq --arg comp "$COMPONENT" '.items[] | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)')

# Extract snapshot
SNAPSHOT=$(echo "$RELEASE_DATA" | jq -r '.spec.snapshot')

# Generate YAML manually
cat <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${COMPONENT}-${VERSION//./-}-${SHA:0:7}-${ENV}-1
  namespace: rhel-ai-tenant
spec:
  releasePlan: ${RPA_NAME}-${ENV}-${VERSION%.*}
  snapshot: ${SNAPSHOT}
EOF
```

## Special Use Cases

### RHEL AI Release Workflow

For RHEL AI production releases, use this workflow:

**Step 1**: Query stage release by commit SHA and component:
```bash
kubectl get releases -n rhel-ai-tenant \
  -l "pac.test.appstudio.openshift.io/sha=<full-sha>" -o json | \
  jq '.items[] | select(.metadata.labels["appstudio.openshift.io/component"] == "<component>")'
```

**Step 2**: Verify release succeeded:
```bash
# Check if status.conditions[type=Released].status == "True"
kubectl get releases -n rhel-ai-tenant \
  -l "pac.test.appstudio.openshift.io/sha=<full-sha>" -o json | \
  jq '.items[] |
    select(.metadata.labels["appstudio.openshift.io/component"] == "<component>") |
    select(.status.conditions[]? | select(.type=="Released" and .status=="True"))'
```

**Step 3**: Extract all required fields:
```bash
kubectl get releases -n rhel-ai-tenant \
  -l "pac.test.appstudio.openshift.io/sha=<full-sha>" -o json | \
  jq -r --arg comp "<component>" '.items[] |
    select(.metadata.labels["appstudio.openshift.io/component"] == $comp) |
    {
      releaseName: .metadata.name,
      component: .metadata.labels["appstudio.openshift.io/component"],
      application: .metadata.labels["appstudio.openshift.io/application"],
      snapshot: .spec.snapshot,
      releasePlan: .spec.releasePlan,
      pipelineUrl: .metadata.annotations["pac.test.appstudio.openshift.io/log-url"],
      commitSha: .metadata.annotations["pac.test.appstudio.openshift.io/sha"],
      commitUrl: .metadata.annotations["pac.test.appstudio.openshift.io/sha-url"],
      imageUrls: [.status.artifacts.images[]?.urls[]?]
    }'
```

**Step 4**: Generate production release YAML (see "Generate Release Resource YAML" above)

## Query Summary (All Resources)

To get a quick overview of all resources:

```bash
echo "=== PipelineRuns ==="
kubectl get pipelineruns -A --no-headers 2>/dev/null | wc -l
echo ""
echo "=== TaskRuns ==="
kubectl get taskruns -A --no-headers 2>/dev/null | wc -l
echo ""
echo "=== Applications ==="
kubectl get applications -A --no-headers 2>/dev/null | wc -l
echo ""
echo "=== Components ==="
kubectl get components -A --no-headers 2>/dev/null | wc -l
echo ""
echo "=== Releases ==="
kubectl get releases -A --no-headers 2>/dev/null | wc -l
```

## Tips for Output Formatting

1. **Use tables** for multiple resources
2. **Extract status** from `.status.conditions[]` array
3. **Show error messages** from conditions when status is False
4. **Calculate duration** between startTime and completionTime
5. **Group by namespace** when showing all namespaces
6. **Limit output** for large result sets using `jq` slice or `head`

## Common Filters

**Filter by namespace:**
```bash
kubectl get <resource> -n <namespace> -o json
```

**Filter by label:**
```bash
kubectl get <resource> -A -l <label-key>=<label-value> -o json
```

**Recent resources (last N):**
```bash
kubectl get <resource> -A -o json | jq '.items | sort_by(.metadata.creationTimestamp) | reverse | .[0:10]'
```

**Resources created in last 24h:**
```bash
kubectl get <resource> -A -o json | jq --arg date "$(date -u -d '24 hours ago' --iso-8601=seconds)" '.items[] | select(.metadata.creationTimestamp > $date)'
```

## Error Handling

Always check if the resource type exists:
```bash
kubectl get <resource> -A -o json 2>&1 | grep -q "error" && echo "Resource type not found or not accessible"
```

## Response Format

When presenting results:
- Use markdown tables for structured data
- Highlight failures or errors in bold
- Show timestamps in human-readable format when possible
- Provide counts and summaries before detailed listings
- For large result sets, ask if user wants to filter further
