#!/usr/bin/env bash
#
# List available Renovate pipelines in the configured namespace.
# Usage: ./list_pipelines.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
ensure_auth

tkn pipeline list -n "$RENOVATE_NAMESPACE" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null \
    | grep "^renovate-" | sort \
    | jq -Rn '[inputs | split("\t") | {name: .[0], created: .[1]}] | {pipelines: ., count: length}'
