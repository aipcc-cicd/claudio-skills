---
name: kubernetes
description: Interact with Kubernetes clusters using kubectl. This skill should be used when the user asks to get, describe, or inspect Kubernetes resources like pods, deployments, services, or configmaps. Assumes kubectl is installed and context is already configured.
allowed-tools: Bash(kubectl get:*)
---

# Kubernetes

## Overview

Interact with Kubernetes clusters using kubectl command-line operations. This skill provides patterns for common kubectl workflows.

**Prerequisites:**
- `kubectl` command is available
- Kubernetes context is already configured (user is logged in)
- `jq` available for JSON parsing (optional)

**Scope:**
This skill covers kubectl operations for inspecting and managing cluster resources. For cluster configuration or advanced troubleshooting, additional research may be needed.

**Workflow Philosophy:**
Always start with default table output to identify resources, then drill down with JSON on specific resources. This avoids context pollution from dumping large JSON outputs when only one resource is relevant.

## Get Operations

Use `kubectl get` to retrieve and list Kubernetes resources.

### Basic Syntax

```bash
# Get resources in a namespace
kubectl get <resource-type> -n <namespace>

# Get across all namespaces
kubectl get <resource-type> -A

# Get specific resource by name
kubectl get <resource-type> <name> -n <namespace>
```

### Label Filtering

```bash
# Filter by label
kubectl get <resource-type> -n <namespace> -l <label-selector>

# Examples:
-l app=nginx                    # Single label
-l app=nginx,env=prod          # Multiple labels (AND)
-l 'env in (prod,staging)'     # Set-based
```

### Critical Workflow: Default First, Then JSON Drill-Down

**Always follow this pattern to avoid context pollution:**

1. Start with default table output
2. Identify the specific resource you need
3. Get only that resource as JSON

```bash
# Step 1: Get table view
kubectl get pods -n production -l app=api
# See 3 pods: 2 Running, 1 Error

# Step 2: Drill down to the specific pod
kubectl get pod api-7d9f8b5c-def456 -n production -o json
```

### Output Formats

```bash
kubectl get pods -n default                 # Default table (start here)
kubectl get pods -n default -o wide         # Wide output (adds IP, node)
kubectl get pod <name> -n default -o json   # JSON (specific resource only)
```

### Using jq for Field Extraction

```bash
# Extract from a specific resource (preferred)
kubectl get pod <name> -n <namespace> -o json | jq -r '.status.podIP'
kubectl get deployment <name> -n <namespace> -o json | jq -r '.spec.template.spec.containers[].image'

# If you must query multiple resources, filter early with labels
kubectl get pods -n default -l app=frontend -o json | jq -r '.items[] | select(.status.phase=="Running") | .metadata.name'
```

### Common Patterns

```bash
kubectl get pods,services,deployments -n <namespace>   # Multiple resource types
kubectl get pods -n <namespace> -w                      # Watch for changes
kubectl get pods -n <namespace> --sort-by=.metadata.creationTimestamp
```

### Example Workflow

**Investigating a failing pod:**

```bash
# 1. Get table view first
kubectl get pods -n production -l app=frontend
# Output shows 3 pods: 2 Running, 1 CrashLoopBackOff

# 2. Drill down to the failing pod
kubectl get pod frontend-7d9f8b5c-abc123 -n production -o json

# 3. Extract specific field if needed
kubectl get pod frontend-7d9f8b5c-abc123 -n production -o json | jq -r '.status.containerStatuses[].lastState.terminated.reason'
```

## Describe Operations

**[To be expanded]**

Use `kubectl describe` to get detailed information about a specific resource, including events.

**Basic usage:**
```bash
kubectl describe <resource-type> <resource-name> -n <namespace>
```

**Examples:**
```bash
# Describe a specific pod
kubectl describe pod <pod-name> -n <namespace>

# Describe a deployment
kubectl describe deployment <deploy-name> -n <namespace>

# Describe a node
kubectl describe node <node-name>
```

## Apply Operations

**[To be expanded]**

Use `kubectl apply` to create or update resources from YAML/JSON manifests.

**Basic usage:**
```bash
kubectl apply -f <file.yaml>
kubectl apply -f <directory/>
```

## Best Practices

**Critical: Always start with default table output**
- Get table view first to see what exists
- Identify the specific resource you need
- Then get only that resource as JSON
- Never dump all resources as JSON unless absolutely necessary

**Context efficiency:**
- Always specify namespace (`-n <namespace>`) to reduce query scope
- Use label selectors to narrow results before fetching JSON
- Get single resources with `-o json`, not collections

**Context commands:**
```bash
kubectl config current-context                # Check current context
kubectl config use-context <context-name>     # Switch context
```

## Dependencies

**Required:**
- `kubectl` - Kubernetes command-line tool

**Optional (for advanced filtering):**
- `jq` - JSON processor for extracting specific fields
- `grep` - Pattern matching (usually pre-installed)
