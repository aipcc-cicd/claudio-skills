#!/usr/bin/env bash
#
# Common helpers for jira-utilities scripts.
# Sourced by all scripts in this directory.
#
# Required environment variables:
#   JIRA_SITE   - Atlassian site hostname (e.g., yourorg.atlassian.net)
#   JIRA_TOKEN  - API token from Atlassian account settings -> Security -> API tokens
#   JIRA_EMAIL  - Your Atlassian account email

# Validate required env vars and exit with code 1 if any are missing
require_env() {
    local missing=()
    for var in JIRA_SITE JIRA_TOKEN JIRA_EMAIL; do
        [[ -z "${!var:-}" ]] && missing+=("$var")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required environment variables: ${missing[*]}" >&2
        echo "  JIRA_SITE  = Atlassian site hostname (e.g., yourorg.atlassian.net)" >&2
        echo "  JIRA_TOKEN = API token from Atlassian account settings" >&2
        echo "  JIRA_EMAIL = Your Atlassian account email" >&2
        exit 1
    fi
}

# Authenticate acli using env vars.
# acli stores credentials in ~/.config/acli/ after login.
# Skips the network round-trip if credentials for this site are already stored.
ensure_auth() {
    require_env
    # Strip scheme prefix so the grep matches regardless of whether JIRA_SITE
    # was exported as "yourorg.atlassian.net" or "https://yourorg.atlassian.net".
    local site_host="${JIRA_SITE#https://}"
    site_host="${site_host#http://}"
    if grep -qrs "$site_host" "${HOME}/.config/acli/" 2>/dev/null; then
        return 0
    fi
    echo "$JIRA_TOKEN" | acli jira auth login \
        --site "$site_host" \
        --email "$JIRA_EMAIL" \
        --token 2>/dev/null || {
        echo "ERROR: acli authentication failed. Verify JIRA_SITE, JIRA_EMAIL, and JIRA_TOKEN." >&2
        exit 4
    }
}

# Normalize JIRA_SITE to a full https:// URL regardless of how it was exported.
jira_site_url() {
    local site="${JIRA_SITE%/}"
    [[ "$site" != https://* && "$site" != http://* ]] && site="https://${site}"
    echo "$site"
}

# Escape a value for embedding in a JQL string literal (doubles embedded double-quotes).
# Usage: escaped=$(jql_escape "value with \"quotes\"")
jql_escape() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }

# Make a Jira REST API call.
# Usage: jira_rest GET|POST|PUT|DELETE <path> [json_body]
# Output: raw response body (may be empty on 204 No Content)
# Exits non-zero and prints error to stderr on HTTP 4xx/5xx.
jira_rest() {
    require_env
    local method="$1" path="$2" body="${3:-}"
    local curl_args=(-s -u "${JIRA_EMAIL}:${JIRA_TOKEN}" -H "Content-Type: application/json")
    [[ -n "$body" ]] && curl_args+=(-d "$body")
    local tmp_body http_code response
    tmp_body=$(mktemp)
    http_code=$(curl "${curl_args[@]}" -X "$method" "$(jira_site_url)${path}" \
        -o "$tmp_body" -w '%{http_code}')
    response=$(cat "$tmp_body")
    rm -f "$tmp_body"
    if [[ "$http_code" -ge 400 ]]; then
        echo "ERROR: Jira API returned HTTP $http_code for $method $path" >&2
        echo "$response" >&2
        return 1
    fi
    echo "$response"
}

# Write JSON to a temp file and echo the path.
# Caller is responsible for cleanup (use: trap "rm -f $TMPFILE" EXIT).
make_tmp_json() {
    local json="$1"
    local tmp
    tmp=$(mktemp /tmp/acli-jira-XXXXXX.json)
    echo "$json" > "$tmp"
    echo "$tmp"
}
