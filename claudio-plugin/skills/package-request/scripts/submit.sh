#!/usr/bin/env bash
# Submits a package onboarding request by creating a Jira epic and triggering
# the package-onboarding GitLab pipeline. Validates against PyPI, checks for
# duplicates, and warns if the package already exists in production repos.
#
# Output protocol: first line is a result type
# (SUCCESS | PRODUCTION_WARNING | DUPLICATE | VALIDATION_ERROR),
# remaining lines are JSON.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIRA_UTILS="$(cd "$SCRIPT_DIR/../../jira-utilities/scripts" && pwd)"
source "$JIRA_UTILS/_common.sh"
source "$SCRIPT_DIR/_format.sh"
source "$SCRIPT_DIR/_validate.sh"
source "$SCRIPT_DIR/_production_check.sh"

EXIT_INVALID_PARAMS=1
EXIT_NETWORK_ERROR=2
EXIT_AUTH_ERROR=3

JIRA_PROJECT="${JIRA_PROJECT:-AIPCC}"
JIRA_COMPONENT="${JIRA_COMPONENT:-Accelerator Enablement}"
JIRA_EPIC_NAME_FIELD="${JIRA_EPIC_NAME_FIELD:-customfield_10011}"
JIRA_TARGET_VERSION_FIELD="${JIRA_TARGET_VERSION_FIELD:-customfield_10855}"
PACKAGE_INDEX_BASE_URL="${PACKAGE_INDEX_BASE_URL:-https://packages.redhat.com/api/pypi/public-rhai/rhoai}"
PACKAGE_INDEX_PRODUCT_VERSIONS="${PACKAGE_INDEX_PRODUCT_VERSIONS:-3.4,3.5}"
PACKAGE_INDEX_VARIANTS="${PACKAGE_INDEX_VARIANTS:-cpu-ubi9}"
DUPLICATE_CHECK_DAYS=3
DUPLICATE_MAX_RESULTS=5
GITLAB_PIPELINE_PROJECT="redhat/rhel-ai/core/package-onboarding"

# ---------------------------------------------------------------------------
# Jira operations (create epic, set target version)
# ---------------------------------------------------------------------------

create_epic() {
    local summary="$1"
    local epic_name="$2"
    local account_id="$3"
    local team="$4"
    local delivery="$5"
    local description="$6"

    local team_label
    team_label=$(sanitize_team_label "$team")

    local labels_json
    labels_json=$(jq -n --arg tl "$team_label" '["package", $tl]')

    local payload
    payload=$(jq -n \
        --arg project "$JIRA_PROJECT" \
        --arg summary "$summary" \
        --arg epic_field "$JIRA_EPIC_NAME_FIELD" \
        --arg epic_name "$epic_name" \
        --arg account_id "$account_id" \
        --argjson labels "$labels_json" \
        --arg component "$JIRA_COMPONENT" \
        --arg duedate "$delivery" \
        --arg description "$description" \
        '{
            fields: {
                project: {key: $project},
                issuetype: {name: "Epic"},
                summary: $summary,
                ($epic_field): $epic_name,
                reporter: {accountId: $account_id},
                labels: $labels,
                duedate: $duedate,
                description: $description,
                security: {name: "Red Hat Employee"}
            }
        }
        | if $component != "" then .fields.components = [{name: $component}] else . end')

    local response
    set +e
    response=$(jira_rest POST "/rest/api/2/issue" "$payload" 2>&1)
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "Failed to create Jira epic: ${response}" >&2
        exit "$EXIT_NETWORK_ERROR"
    fi

    local ticket_id
    ticket_id=$(echo "$response" | jq -r '.key')
    if [[ -z "$ticket_id" || "$ticket_id" == "null" ]]; then
        echo "Failed to parse ticket ID from response: ${response}" >&2
        exit "$EXIT_NETWORK_ERROR"
    fi

    echo "$ticket_id"
}

update_target_version() {
    local ticket_id="$1"
    local release_target="$2"

    local versions_json
    versions_json=$(echo "$release_target" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map({name: .})')

    local payload
    payload=$(jq -n --arg field "$JIRA_TARGET_VERSION_FIELD" --argjson versions "$versions_json" \
        '{fields: {($field): $versions}}')

    set +e
    jira_rest PUT "/rest/api/2/issue/${ticket_id}" "$payload" >/dev/null 2>&1
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "Warning: Failed to set Target Version on ${ticket_id}" >&2
    fi
}

# ---------------------------------------------------------------------------
# GitLab pipeline trigger (non-blocking)
# ---------------------------------------------------------------------------

trigger_pipeline() {
    local package_with_extras="$1"
    local ticket_id="$2"
    local version="${3:-}"

    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
        echo "Warning: GITLAB_TOKEN not set, skipping pipeline trigger" >&2
        return 0
    fi

    if ! command -v glab >/dev/null 2>&1; then
        echo "Warning: glab not found, skipping pipeline trigger" >&2
        return 0
    fi

    local vars_file
    vars_file=$(mktemp /tmp/pipeline-vars-XXXXXX.json)
    trap 'rm -f "$vars_file"' RETURN

    jq -n \
        --arg pkg "$package_with_extras" \
        --arg tid "$ticket_id" \
        '[{key: "PACKAGE_NAME", value: $pkg}, {key: "JIRA_TICKET_ID", value: $tid}]' > "$vars_file"
    if [[ -n "$version" ]]; then
        local updated
        updated=$(jq --arg ver "$version" '. + [{key: "PACKAGE_VERSION", value: $ver}]' "$vars_file")
        printf '%s' "$updated" > "$vars_file"
    fi

    local output
    set +e
    output=$(glab ci run -R "$GITLAB_PIPELINE_PROJECT" -b main --variables-from "$vars_file" 2>&1)
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
        echo "Warning: Pipeline trigger failed: ${output}" >&2
        return 0
    fi

    local pipeline_url
    pipeline_url=$(echo "$output" | grep -oE 'https://[^ ]*pipelines/[0-9]+' | head -1)
    if [[ -z "$pipeline_url" ]]; then
        pipeline_url=$(echo "$output" | grep -oE 'https://[^ ]+' | head -1)
    fi
    echo "${pipeline_url:-}"
}

# ===========================================================================
# Arg parsing
# ===========================================================================

package_name=""
requester=""
team=""
jira_id=""
justification=""
delivery_timeline=""

extras=""
package_source=""
source_url=""
version=""
backport_versions=""
release_target=""
release_commitment=""
other_hardware=""
testing_requirements=""
skip_production_check=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package-name)        package_name="$2"; shift 2 ;;
        --requester)           requester="$2"; shift 2 ;;
        --team)                team="$2"; shift 2 ;;
        --jira-id)             jira_id="$2"; shift 2 ;;
        --justification)       justification="$2"; shift 2 ;;
        --delivery-timeline)   delivery_timeline="$2"; shift 2 ;;
        --extras)              extras="$2"; shift 2 ;;
        --package-source)      package_source="$2"; shift 2 ;;
        --source-url)          source_url="$2"; shift 2 ;;
        --version)             version="$2"; shift 2 ;;
        --backport-versions)   backport_versions="$2"; shift 2 ;;
        --release-target)      release_target="$2"; shift 2 ;;
        --release-commitment)  release_commitment="$2"; shift 2 ;;
        --other-hardware)      other_hardware="$2"; shift 2 ;;
        --testing-requirements) testing_requirements="$2"; shift 2 ;;
        --skip-production-check) skip_production_check=true; shift ;;
        *)
            echo "Unknown argument: $1" >&2
            exit "$EXIT_INVALID_PARAMS"
            ;;
    esac
done

# ===========================================================================
# Validate required fields
# ===========================================================================

missing=()
[[ -z "$package_name" ]]      && missing+=("--package-name")
[[ -z "$requester" ]]         && missing+=("--requester")
[[ -z "$team" ]]              && missing+=("--team")
[[ -z "$jira_id" ]]           && missing+=("--jira-id")
[[ -z "$justification" ]]     && missing+=("--justification")
[[ -z "$delivery_timeline" ]] && missing+=("--delivery-timeline")

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required arguments: ${missing[*]}" >&2
    exit "$EXIT_INVALID_PARAMS"
fi

if ! [[ "$delivery_timeline" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Invalid --delivery-timeline format: '${delivery_timeline}'. Must be YYYY-MM-DD." >&2
    exit "$EXIT_INVALID_PARAMS"
fi

# Parse extras from package name if present (e.g. torch[cuda,tensor])
if [[ "$package_name" == *"["*"]" ]]; then
    parsed_extras="${package_name#*\[}"
    parsed_extras="${parsed_extras%\]}"
    package_name="${package_name%%\[*}"
    if [[ -n "$extras" ]]; then
        extras="${parsed_extras},${extras}"
    else
        extras="$parsed_extras"
    fi
fi

# Deduplicate extras
if [[ -n "$extras" ]]; then
    extras=$(echo "$extras" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u | paste -sd, -)
fi

package_with_extras="$package_name"
if [[ -n "$extras" ]]; then
    package_with_extras="${package_name}[${extras}]"
fi

summary="${package_with_extras} package update request"
epic_name="${package_name} package update request"

# Validate env vars (subshell because require_env calls exit directly)
if ! (require_env 2>/dev/null); then
    echo "Missing required Jira environment variables (JIRA_SITE, JIRA_TOKEN, JIRA_EMAIL)" >&2
    exit "$EXIT_AUTH_ERROR"
fi

# ===========================================================================
# Execution flow
# ===========================================================================

pkg_source="${package_source:-pypi}"
if [[ "$pkg_source" == "pypi" ]]; then
    validate_pypi "$package_name"
fi

account_id=$(validate_jira_user "$requester")
if [[ "$account_id" == VALIDATION_ERROR* ]]; then
    echo "$account_id"
    exit 0
fi

validate_jira_ticket "$jira_id"

check_duplicates "$summary" "$package_name" "$extras" "$JIRA_PROJECT" "$DUPLICATE_CHECK_DAYS" "$DUPLICATE_MAX_RESULTS"

if [[ "$skip_production_check" != true ]]; then
    check_production_repos "$package_name" "$PACKAGE_INDEX_BASE_URL" "$PACKAGE_INDEX_PRODUCT_VERSIONS" "$PACKAGE_INDEX_VARIANTS"
fi

description=$(format_description \
    "$requester" "$team" "$package_name" "$pkg_source" "$source_url" \
    "$version" "$extras" "$other_hardware" "$jira_id" "$justification" \
    "$delivery_timeline" "$release_commitment" "$testing_requirements" \
    "$backport_versions")

ticket_id=$(create_epic "$summary" "$epic_name" "$account_id" "$team" "$delivery_timeline" "$description")
jira_url=$(jira_site_url)
ticket_url="${jira_url}/browse/${ticket_id}"

if [[ -n "$release_target" ]]; then
    update_target_version "$ticket_id" "$release_target"
fi

pipeline_url=$(trigger_pipeline "$package_with_extras" "$ticket_id" "$version")

echo "SUCCESS"
jq -n \
    --arg tid "$ticket_id" \
    --arg turl "$ticket_url" \
    --arg pkg "$package_with_extras" \
    --arg msg "Package request created successfully" \
    --arg purl "${pipeline_url:-}" \
    '{
        ticket_id: $tid,
        ticket_url: $turl,
        package_name: $pkg,
        message: $msg
    }
    | if $purl != "" then . + {pipeline_url: $purl} else . end'
