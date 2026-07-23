# Output helpers, PEP 503 normalization, team label sanitization,
# and Jira wiki markup description formatting.
# Sourced by submit.sh — not executed directly.

# ---------------------------------------------------------------------------
# Output helpers — result type on first line, JSON on remaining
# ---------------------------------------------------------------------------

output_result() {
    local type="$1"; shift
    echo "$type"
    echo "$@"
}

output_error() {
    local type="$1" message="$2"
    echo "$type"
    jq -n --arg msg "$message" '{"message": $msg}'
}

# ---------------------------------------------------------------------------
# PEP 503 package name normalization
# ---------------------------------------------------------------------------

normalize_pep503() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[-_.]\{1,\}/-/g'
}

# ---------------------------------------------------------------------------
# Sanitize team name for Jira label: "AI Core Platform" -> "team-ai-core-platform"
# ---------------------------------------------------------------------------

sanitize_team_label() {
    local team="$1"
    local label
    label=$(echo "$team" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')
    echo "team-${label}"
}

# ---------------------------------------------------------------------------
# Format Jira wiki markup description
# ---------------------------------------------------------------------------

format_description() {
    local requester="$1"
    local team="$2"
    local pkg_name="$3"
    local pkg_source="$4"
    local source_url="$5"
    local ver="$6"
    local extras_str="$7"
    local other_hw="$8"
    local jira_id="$9"
    local justification="${10}"
    local delivery="${11}"
    local release_commitment="${12}"
    local testing_req="${13}"
    local backport_versions="${14}"

    local desc=""
    desc+="h2. Package Request Details"$'\n'
    desc+=$'\n'
    desc+="*Requester:* ${requester}"$'\n'
    desc+="*Team:* ${team}"$'\n'
    desc+="*Package Name:* ${pkg_name}"$'\n'
    desc+="*Package Source:* ${pkg_source:-pypi}"$'\n'
    desc+="*Source URL:* ${source_url:-N/A}"$'\n'
    desc+="*Version:* ${ver:-Latest}"$'\n'
    if [[ -n "$extras_str" ]]; then
        desc+="*Extras:* ${extras_str}"$'\n'
    fi
    desc+="*Hardware Requirements:* ${other_hw:-Standard (all accelerators)}"$'\n'
    desc+=$'\n'
    desc+="h2. Business Justification"$'\n'
    desc+="*Related Jira Ticket:* ${jira_id}"$'\n'
    desc+=$'\n'
    desc+="${justification}"$'\n'
    desc+=$'\n'
    desc+="h2. Delivery Timeline"$'\n'
    desc+="*Target Date:* ${delivery}"$'\n'
    if [[ -n "$release_commitment" ]]; then
        desc+="*Release Commitment:* ${release_commitment}"$'\n'
    fi
    desc+=$'\n'
    desc+="h2. Testing Requirements"$'\n'
    desc+="${testing_req:-Default probe tests only}"$'\n'

    if [[ -n "$backport_versions" ]]; then
        desc+=$'\n'
        desc+="h2. Backport Targets"$'\n'
        IFS=',' read -ra bp_arr <<< "$backport_versions"
        for bp in "${bp_arr[@]}"; do
            bp=$(echo "$bp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            desc+="* ${bp}"$'\n'
        done
    fi

    desc+=$'\n'
    desc+="----"$'\n'
    desc+="_This request was automatically created via the Claudio Package Request Skill._"

    echo "$desc"
}
