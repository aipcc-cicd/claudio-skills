#!/bin/bash
# Generate Konflux Release YAML from stage release information
#
# Usage: generate-release-yaml.sh [OPTIONS]
#
# Options:
#   -c, --component COMPONENT    Component name (e.g., bootc-cuda)
#   -s, --sha SHA                Full commit SHA (40 characters)
#   -v, --version VERSION        Version in semver format (e.g., 3.0.0)
#   -e, --env ENVIRONMENT        Environment: stage or prod
#   -n, --namespace NAMESPACE    Kubernetes namespace (default: rhel-ai-tenant)
#   -r, --rpa RPA_NAME           RPA group name (e.g., bootc-containers)
#   -o, --output FILE            Output file (default: stdout)
#   -h, --help                   Show this help message

set -euo pipefail

# Default values
NAMESPACE="rhel-ai-tenant"
OUTPUT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--component)
      COMPONENT="$2"
      shift 2
      ;;
    -s|--sha)
      SHA="$2"
      shift 2
      ;;
    -v|--version)
      VERSION="$2"
      shift 2
      ;;
    -e|--env)
      ENV="$2"
      shift 2
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -r|--rpa)
      RPA_NAME="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT="$2"
      shift 2
      ;;
    -h|--help)
      grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# //' | head -n 10
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "${COMPONENT:-}" ]]; then
  echo "Error: --component is required" >&2
  exit 1
fi

if [[ -z "${SHA:-}" ]]; then
  echo "Error: --sha is required" >&2
  exit 1
fi

if [[ -z "${VERSION:-}" ]]; then
  echo "Error: --version is required" >&2
  exit 1
fi

if [[ -z "${ENV:-}" ]]; then
  echo "Error: --env is required" >&2
  exit 1
fi

if [[ -z "${RPA_NAME:-}" ]]; then
  echo "Error: --rpa is required" >&2
  exit 1
fi

# Validate SHA length
if [[ ${#SHA} -ne 40 ]]; then
  echo "Error: SHA must be 40 characters (full SHA), got ${#SHA}" >&2
  exit 1
fi

# Validate environment
if [[ "$ENV" != "stage" && "$ENV" != "prod" ]]; then
  echo "Error: --env must be 'stage' or 'prod', got '$ENV'" >&2
  exit 1
fi

# Query stage release by SHA and component
echo "Querying stage release for ${COMPONENT} @ ${SHA:0:7}..." >&2

RELEASE_DATA=$(kubectl get releases -n "$NAMESPACE" \
  -l "pac.test.appstudio.openshift.io/sha=${SHA}" -o json 2>/dev/null | \
  jq --arg comp "$COMPONENT" '.items[] | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)' 2>/dev/null)

if [[ -z "$RELEASE_DATA" ]]; then
  echo "Error: No release found for component '$COMPONENT' with SHA '$SHA'" >&2
  exit 1
fi

# Verify release succeeded
RELEASE_STATUS=$(echo "$RELEASE_DATA" | jq -r '.status.conditions[]? | select(.type=="Released") | .status' 2>/dev/null || echo "")

if [[ "$RELEASE_STATUS" != "True" ]]; then
  echo "Error: Release for component '$COMPONENT' has not succeeded (status: ${RELEASE_STATUS:-Unknown})" >&2
  exit 1
fi

# Extract snapshot name
SNAPSHOT=$(echo "$RELEASE_DATA" | jq -r '.spec.snapshot' 2>/dev/null)

if [[ -z "$SNAPSHOT" || "$SNAPSHOT" == "null" ]]; then
  echo "Error: Could not extract snapshot from release" >&2
  exit 1
fi

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

# Format version for naming: M-m-p (e.g., 3-0-0)
VERSION_DASH="${MAJOR}-${MINOR}-${PATCH}"

# Format version for release plan: M-m (e.g., 3-0)
VERSION_SHORT="${MAJOR}-${MINOR}"

# Extract short SHA (first 7 characters)
SHORT_SHA="${SHA:0:7}"

# Generate release name: <component>-<M-m-p>-<short-sha>-<env>-1
RELEASE_NAME="${COMPONENT}-${VERSION_DASH}-${SHORT_SHA}-${ENV}-1"

# Generate release plan name: <rpa>-<env>-<M-m>
RELEASE_PLAN="${RPA_NAME}-${ENV}-${VERSION_SHORT}"

# Generate YAML
YAML=$(cat <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${RELEASE_NAME}
  namespace: ${NAMESPACE}
spec:
  releasePlan: ${RELEASE_PLAN}
  snapshot: ${SNAPSHOT}
EOF
)

# Output to file or stdout
if [[ -n "$OUTPUT" ]]; then
  echo "$YAML" > "$OUTPUT"
  echo "Generated release YAML: $OUTPUT" >&2
  echo "  Component: $COMPONENT" >&2
  echo "  Snapshot: $SNAPSHOT" >&2
  echo "  Release Plan: $RELEASE_PLAN" >&2
  echo "  Release Name: $RELEASE_NAME" >&2
else
  echo "$YAML"
fi
