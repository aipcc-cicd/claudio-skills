---
name: containers
description: Work with container images using skopeo and other container tools. Inspect image metadata, labels, and tags from various registries.
allowed-tools: Bash(skopeo inspect:*)
---

# Containers

## Overview

Work with container images using `skopeo` for inspection and metadata retrieval.

**Current tools:**
- `skopeo` - Container image inspection without pulling images

**Future expansion:**
- `podman` - Container runtime and management
- `oras` - OCI registry operations

## Prerequisites

**Required:**
- `skopeo` - Container image inspector

**Optional:**
- `jq` - JSON processor for parsing output

## Image Inspection

Use `skopeo inspect` to retrieve image metadata without pulling the image:

```bash
skopeo inspect docker://quay.io/organization/image:tag
```

**Transport prefixes:**
- `docker://` - Remote registry (most common)
- `docker-daemon:` - Local Docker daemon
- `oci:` - OCI layout directory
- `dir:` - Plain directory

**Common registries:**
- `docker://docker.io/library/alpine:latest`
- `docker://quay.io/organization/image:tag`
- `docker://registry.redhat.io/product/image:version`
- `docker://ghcr.io/owner/repo:tag`

## Extracting Labels

Container labels contain metadata about the image:

**Get all labels:**
```bash
skopeo inspect docker://quay.io/organization/image:tag | jq '.Labels'
```

**Get specific label:**
```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.Labels["com.example.version"]'
```

**Common label patterns:**
- `com.example.*` - Custom application labels
- `org.opencontainers.image.*` - OCI standard labels
- `io.k8s.*` - Kubernetes-related labels

## Extracting Tags

Get available tags for an image:

**List all tags (paginated):**
```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.RepoTags[]'
```

**List first 20 tags:**
```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.RepoTags[:20][]'
```

**Filter tags by pattern:**
```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.RepoTags[] | select(test("^v[0-9]"))'
```

## Other Useful Fields

**Image digest:**
```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.Digest'
```

**Image name:**
```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.Name'
```

**Created timestamp:**
```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.Created'
```

**Architecture:**
```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.Architecture'
```

## Example Workflows

**Find image version from labels:**

User: "What version is this image?"

```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.Labels["version"]'
# or
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.Labels["org.opencontainers.image.version"]'
```

**Get git commit from labels:**

User: "What commit was this image built from?"

```bash
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.Labels["vcs-ref"]'
# or
skopeo inspect docker://quay.io/organization/image:tag | jq -r '.Labels["org.opencontainers.image.revision"]'
```

**List recent version tags:**

User: "Show me the recent version tags for this image"

```bash
skopeo inspect docker://quay.io/organization/image:latest | jq -r '.RepoTags[] | select(test("^[0-9]+\\.[0-9]+"))' | sort -V | tail -10
```

## Best Practices

**Image inspection:**
- Always use `docker://` prefix for remote registries
- Use `jq -r` for raw output (removes quotes)
- Images can be inspected without authentication for public registries

**Authentication:**
- For private registries, use `--creds` flag: `skopeo inspect --creds username:password docker://...`
- Or configure auth in `${XDG_RUNTIME_DIR}/containers/auth.json`

**Performance:**
- `skopeo inspect` is fast - it only fetches metadata, not image layers
- No need to pull entire images to check labels or tags

## Dependencies

**Required:**
- `skopeo` - Container image inspection tool

**Optional:**
- `jq` - JSON processor for parsing skopeo output
