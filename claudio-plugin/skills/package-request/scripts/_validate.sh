# Validation functions: PyPI package existence, Jira user lookup,
# Jira ticket existence, and duplicate request detection.
# Sourced by submit.sh — not executed directly.
# Requires: jira_rest, jira_site_url, jql_escape from jira-utilities _common.sh
# Requires: output_error from _format.sh

# ---------------------------------------------------------------------------
# Validate PyPI package exists (pypi source only)
# Blocks on 404, soft-fails on network errors.
# ---------------------------------------------------------------------------

validate_pypi() {
    local package_name="$1"
    local http_code
    set +e
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 \
        "https://pypi.org/pypi/${package_name}/json" 2>/dev/null)
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "PyPI check failed (network error), proceeding" >&2
        return 0
    fi
    if [[ "$http_code" == "404" ]]; then
        output_error "VALIDATION_ERROR" \
            "Package '${package_name}' not found on PyPI. Verify at https://pypi.org/search/?q=${package_name}"
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# Validate Jira user — smart retry, returns accountId on stdout.
# Input formats: email, kerberos username, or display name.
# ---------------------------------------------------------------------------

validate_jira_user() {
    local input="$1"
    local attempts=()

    if [[ "$input" == *" "* ]]; then
        attempts=("$input")
    elif [[ "$input" == *"@"* ]]; then
        attempts=("$input" "${input%%@*}")
    else
        attempts=("$input" "${input}@redhat.com")
    fi

    for attempt in "${attempts[@]}"; do
        local encoded
        encoded=$(jq -Rr '@uri' <<< "$attempt")
        local response
        set +e
        response=$(jira_rest GET "/rest/api/2/user/search?query=${encoded}&maxResults=5" 2>/dev/null)
        local rc=$?
        set -e
        [[ $rc -ne 0 ]] && continue

        local account_id
        account_id=$(echo "$response" | jq -r --arg attempt "$attempt" '
            [.[] | select(
                (.emailAddress // "" | ascii_downcase) == ($attempt | ascii_downcase) or
                (.displayName // "" | ascii_downcase) == ($attempt | ascii_downcase)
            )] | first // empty | .accountId')

        if [[ -n "$account_id" && "$account_id" != "null" ]]; then
            echo "$account_id"
            return 0
        fi
    done

    output_error "VALIDATION_ERROR" \
        "Unable to find requester '${input}' in Jira. Tried: ${attempts[*]}. Verify the email or username."
    exit 0
}

# ---------------------------------------------------------------------------
# Validate Jira ticket exists
# ---------------------------------------------------------------------------

validate_jira_ticket() {
    local jira_id="$1"
    set +e
    jira_rest GET "/rest/api/2/issue/${jira_id}?fields=key" >/dev/null 2>&1
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        output_error "VALIDATION_ERROR" \
            "Jira ticket '${jira_id}' not found or not accessible. Verify the ticket ID."
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# Check for duplicate requests (last N days).
# Outputs DUPLICATE and exits 0 if found. Soft-fails on errors.
# ---------------------------------------------------------------------------

check_duplicates() {
    local summary="$1"
    local package_name="$2"
    local extras="$3"
    local jira_project="$4"
    local duplicate_days="$5"
    local max_results="$6"

    local escaped_summary
    escaped_summary=$(jql_escape "$summary")
    local summary_conditions="summary ~ \"\\\"${escaped_summary}\\\"\""

    if [[ -n "$extras" && "$extras" == *","* ]]; then
        IFS=',' read -ra extra_arr <<< "$extras"
        for extra in "${extra_arr[@]}"; do
            extra=$(echo "$extra" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local individual_summary="${package_name}[${extra}] package update request"
            local escaped_individual
            escaped_individual=$(jql_escape "$individual_summary")
            summary_conditions="${summary_conditions} OR summary ~ \"\\\"${escaped_individual}\\\"\""
        done
    fi

    local jql="project = \"${jira_project}\" AND (${summary_conditions}) AND labels = \"package\" AND created >= -${duplicate_days}d"
    local encoded_jql
    encoded_jql=$(jq -Rr '@uri' <<< "$jql")

    local response
    set +e
    response=$(jira_rest GET "/rest/api/3/search/jql?jql=${encoded_jql}&maxResults=${max_results}&fields=key,summary" 2>/dev/null)
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
        echo "Duplicate check failed, proceeding with creation" >&2
        return 0
    fi

    local total
    total=$(echo "$response" | jq '.issues | length')
    if [[ "$total" -gt 0 ]]; then
        local jira_url
        jira_url=$(jira_site_url)
        local existing_tickets
        existing_tickets=$(echo "$response" | jq --arg url "$jira_url" '[.issues[] | {
            ticket_id: .key,
            ticket_url: ($url + "/browse/" + .key),
            summary: (.fields.summary // "")
        }]')
        echo "DUPLICATE"
        jq -n --arg pkg "$summary" \
              --argjson tickets "$existing_tickets" \
              --argjson total "$total" \
              --arg days "$duplicate_days" \
            '{
                message: ("A request overlapping with \"" + $pkg + "\" was submitted in the past " + $days + " days."),
                existing_tickets: $tickets,
                total: $total
            }'
        exit 0
    fi
}
