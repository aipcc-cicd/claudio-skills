# Konflux Release Statistics

Generate comprehensive build and release statistics for a Konflux application.

## Overview

This skill analyzes Konflux resources in a Kubernetes namespace to provide detailed statistics about:
- Build timeline and snapshot counts
- Stage and production releases
- Integration test scenarios and results
- Component deployment status

## Usage

```
/konflux-release-stats <application-name> [namespace]
```

**Parameters:**
- `application-name`: The Konflux application name (e.g., "myproduct-1-2-3")
- `namespace`: Optional. Kubernetes namespace (default: "ai-tenant")

**Examples:**
```bash
/konflux-release-stats myproduct-1-2-3
/konflux-release-stats myproduct-2-0-0 production-namespace
```

## Methodology

### Step 1: Verify Application Exists
```bash
kubectl get application <app-name> -n <namespace>
```

### Step 2: Gather Build Statistics
```bash
# Count total snapshots
kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' --no-headers | wc -l

# Get first build timestamp
kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items | sort_by(.metadata.creationTimestamp) | .[0] | .metadata.creationTimestamp'

# Count primary builds (excluding component-specific retries with suffix like -xy)
kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items[] | .metadata.name' | grep -v '\-[a-z0-9]\{2\}$' | wc -l

# List all snapshots sorted by creation time
kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' \
  --sort-by=.metadata.creationTimestamp
```

### Step 3: Gather Release Statistics
```bash
# Count total releases
kubectl get releases -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' --no-headers | wc -l

# Count stage releases
kubectl get releases -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items[] | select(.spec.releasePlan | contains("stage")) | .metadata.name' | wc -l

# List production releases with timestamps
kubectl get releases -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' \
  --sort-by=.metadata.creationTimestamp

# Get first production release timestamp
kubectl get releases -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items[] | select(.spec.releasePlan | contains("prod")) | .metadata.creationTimestamp' | \
  sort | head -1

# List all production releases
kubectl get releases -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items[] | select(.spec.releasePlan | contains("prod")) | .metadata.name'
```

### Step 4: Calculate Timeline
```bash
# Calculate days from first build to first production release
first_build=$(kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items | sort_by(.metadata.creationTimestamp) | .[0] | .metadata.creationTimestamp')

first_prod=$(kubectl get releases -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items[] | select(.spec.releasePlan | contains("prod")) | .metadata.creationTimestamp' | \
  sort | head -1)

# Calculate difference in days
python3 -c "from datetime import datetime; print(round((datetime.fromisoformat('${first_prod}'.replace('Z', '+00:00')) - datetime.fromisoformat('${first_build}'.replace('Z', '+00:00'))).total_seconds() / 86400, 1))"
```

### Step 5: Analyze Integration Tests
```bash
# Check snapshot test status
kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '[.items[].status.conditions[] | select(.type=="AppStudioTestSucceeded") | .message] | unique[]'

# Count snapshots with integration tests
kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items[] | select(.status.conditions[] | select(.type=="AppStudioTestSucceeded" and .message=="All Integration Pipeline tests passed")) | .metadata.name' | wc -l

# Extract test results from all snapshots
for snap in $(kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o jsonpath='{.items[*].metadata.name}'); do
  kubectl get snapshot $snap -n <namespace> -o jsonpath="{.metadata.annotations.test\.appstudio\.openshift\.io/status}"
done | grep -v '^$' | jq -r '.[].scenario' | sort | uniq -c | sort -rn

# Get test pass/fail breakdown
for snap in $(kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o jsonpath='{.items[*].metadata.name}'); do
  kubectl get snapshot $snap -n <namespace> -o jsonpath="{.metadata.annotations.test\.appstudio\.openshift\.io/status}"
done | grep -v '^$' | jq -r '.[] | "\(.scenario)|\(.status)"' | sort | uniq -c | sort -k2
```

### Step 6: Get Integration Test Scenario Details
```bash
# List all integration test scenarios for the application
kubectl get integrationtestscenario -n <namespace> | grep <app-name>

# Get details for each scenario
kubectl get integrationtestscenario <scenario-name> -n <namespace> -o yaml
```

### Step 7: Identify Released Components
```bash
# Get unique components from snapshots
kubectl get snapshots -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items[].spec.components[].name' | sort -u

# Get production releases and their associated components
kubectl get releases -n <namespace> -l 'appstudio.openshift.io/application=<app-name>' -o json | \
  jq -r '.items[] | select(.spec.releasePlan | contains("prod")) | "\(.metadata.name) -> \(.spec.snapshot)"'
```

## Output Format

The skill should produce a structured summary containing:

### Timeline Section
- First build timestamp
- First production release timestamp
- Days from first build to production

### Build & Release Counts
- Total snapshots
- Primary build iterations
- Stage releases count
- Production releases count

### Integration Test Services
For each test scenario:
- Test name and purpose
- Components tested
- Architecture/configuration
- Pipeline location
- Test results (passed/failed counts and percentages)

### Test Coverage Summary
- Total test executions
- Snapshots with tests vs without
- Overall pass rate
- Test period

### Components Released
- List of production components with timestamps
- Release plan classification (GA vs Tech Preview)

### Additional Components
- Components built but not released

## Requirements

**Tools:**
- `kubectl` - Kubernetes CLI (authenticated to cluster)
- `jq` - JSON processor
- `python3` - For date calculations

**Permissions:**
- Read access to namespace resources:
  - applications
  - components
  - snapshots
  - releases
  - integrationtestscenarios

## Notes

- Integration tests are tracked in snapshot annotations under `test.appstudio.openshift.io/status`
- Component-specific builds typically have a 2-character suffix (e.g., `-xy`, `-ab`)
- Stage releases use release plans containing "stage"
- Production releases use release plans containing "prod"
- Test scenarios marked as "optional" allow auto-release even if tests fail
