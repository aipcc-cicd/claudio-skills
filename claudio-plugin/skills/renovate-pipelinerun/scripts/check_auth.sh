#!/usr/bin/env bash
#
# Check OpenShift cluster authentication and namespace configuration.
# Usage: ./check_auth.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
ensure_auth

user=$(kubectl auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null || echo "unknown")
server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "unknown")
echo "{\"status\": \"authenticated\", \"user\": \"$user\", \"server\": \"$server\", \"namespace\": \"$RENOVATE_NAMESPACE\"}"
