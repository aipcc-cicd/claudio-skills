#!/usr/bin/env bash
# Create a GitLab branch and protect it with configurable rules
#
# Usage:
#   create_and_protect_branch.sh <repo> <branch-name> <ref> [OPTIONS]
#
# Examples:
#   ./create_and_protect_branch.sh my-project release-1.5 v1.4.0
#   ./create_and_protect_branch.sh my-org/my-group/my-project release-1.5 v1.4.0
#   ./create_and_protect_branch.sh my-project release-1.5 main --push-level 40 --merge-level 40
#   ./create_and_protect_branch.sh my-project release-1.5 v1.4.0 --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    cat << 'EOF'
Usage: create_and_protect_branch.sh <repo> <branch-name> <ref> [OPTIONS]

Create a GitLab branch and protect it with configurable rules.

ARGUMENTS:
    repo                   Repository: short name, full path, or URL
    branch-name            Name for the new branch
    ref                    Source ref to branch from (tag, commit SHA, or branch)

OPTIONS:
    --push-level N         Push access level (default: 0 = No access)
    --merge-level N        Merge access level (default: 40 = Maintainer)
    --unprotect-level N    Unprotect access level (default: not set)
    --allow-force-push     Allow force push (default: blocked)
    --code-owner-approval  Require code owner approval (default: not required)
    --gitlab-host HOST     GitLab hostname (default: gitlab.com)
    --rule KEY=VALUE       Override any protection rule by key
    --dry-run              Show planned actions, make no API calls
    --human-readable       Human-readable output instead of JSON
    -h, --help             Show this help message

ACCESS LEVELS:
    0   No access
    30  Developer
    40  Maintainer

EXAMPLES:
    # Create and protect with defaults (strict lockdown)
    create_and_protect_branch.sh my-project release-1.5 v1.4.0

    # Branch from a tag
    create_and_protect_branch.sh my-org/my-group/my-project release-1.5 v1.4.0

    # Custom protection
    create_and_protect_branch.sh my-project release-1.5 v1.4.0 --push-level 40 --merge-level 40

    # Dry run
    create_and_protect_branch.sh my-project release-1.5 v1.4.0 --dry-run

    # Generic rule override
    create_and_protect_branch.sh my-project release-1.5 v1.4.0 --rule merge_access_level=30
EOF
}

# --- Protection rules (extensible) ---
# Parallel arrays for bash 3.2+ compatibility.
# To add a new rule: append key to RULE_KEYS and default value to RULE_VALS.
# CLI flags and --rule KEY=VALUE override defaults.
RULE_KEYS=(allow_force_push code_owner_approval_required merge_access_level push_access_level)
RULE_VALS=(false             false                        40                  0)

# --- Rule helpers ---

# Get index of a key, or -1 if not found
rule_index() {
    local target="$1"
    local i
    for i in $(seq 0 $((${#RULE_KEYS[@]} - 1))); do
        if [ "${RULE_KEYS[$i]}" = "$target" ]; then
            echo "$i"
            return 0
        fi
    done
    echo "-1"
    return 1
}

# Get value for a key
rule_get() {
    local idx
    idx=$(rule_index "$1") || { echo ""; return 1; }
    echo "${RULE_VALS[$idx]}"
}

# Set value for a key (adds if new)
rule_set() {
    local key="$1"
    local val="$2"
    local idx
    if idx=$(rule_index "$key"); then
        RULE_VALS[$idx]="$val"
    else
        # New key — insert in sorted order
        local new_keys=()
        local new_vals=()
        local inserted=false
        local i
        for i in $(seq 0 $((${#RULE_KEYS[@]} - 1))); do
            if [ "$inserted" = false ] && [[ "$key" < "${RULE_KEYS[$i]}" ]]; then
                new_keys+=("$key")
                new_vals+=("$val")
                inserted=true
            fi
            new_keys+=("${RULE_KEYS[$i]}")
            new_vals+=("${RULE_VALS[$i]}")
        done
        if [ "$inserted" = false ]; then
            new_keys+=("$key")
            new_vals+=("$val")
        fi
        RULE_KEYS=("${new_keys[@]}")
        RULE_VALS=("${new_vals[@]}")
    fi
}

# --- Helpers ---

log() {
    echo "$*" >&2
}

check_deps() {
    if ! command -v glab &>/dev/null; then
        echo '{"error":"glab is required but not found. Install via tools/glab/install.sh"}' >&2
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo '{"error":"jq is required but not found. Install via tools/jq/install.sh"}' >&2
        exit 1
    fi
}

json_error() {
    local error="$1"
    local repo="${2:-}"
    local branch="${3:-}"
    jq -n \
        --arg error "$error" \
        --arg repo "$repo" \
        --arg branch "$branch" \
        '{error: $error, repository: $repo, branch: $branch}'
}

url_encode() {
    local string="$1"
    local encoded=""
    local i char
    for ((i = 0; i < ${#string}; i++)); do
        char="${string:$i:1}"
        case "$char" in
            [a-zA-Z0-9._~-]) encoded+="$char" ;;
            *) encoded+=$(printf '%%%02X' "'$char") ;;
        esac
    done
    echo "$encoded"
}

# Wrapper for glab api that includes --hostname
glab_api() {
    glab api --hostname "$GITLAB_HOST" "$@"
}

# Build protection rules JSON fragment
build_rules_json() {
    local json="{}"
    local i
    for i in $(seq 0 $((${#RULE_KEYS[@]} - 1))); do
        local key="${RULE_KEYS[$i]}"
        local val="${RULE_VALS[$i]}"
        if [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" == "true" ]] || [[ "$val" == "false" ]]; then
            json=$(echo "$json" | jq --arg k "$key" --argjson v "$val" '. + {($k): $v}')
        else
            json=$(echo "$json" | jq --arg k "$key" --arg v "$val" '. + {($k): $v}')
        fi
    done
    echo "$json"
}

# --- Repo resolution ---

# Validate that a resolved repo path exists on GitLab
validate_repo() {
    local repo_path="$1"
    local encoded
    encoded=$(url_encode "$repo_path")
    local result
    if ! result=$(glab_api --method GET "projects/$encoded" 2>/dev/null); then
        json_error "Repository '$repo_path' not found on GitLab" "$repo_path" ""
        return 1
    fi
    return 0
}

resolve_repo() {
    local input="$1"
    local resolved_path=""

    # URL format: https://gitlab.com/group/repo.git or git@gitlab.com:group/repo.git
    if [[ "$input" == *"://"* ]]; then
        resolved_path="${input#*://}"
        resolved_path="${resolved_path#*/}"  # Remove host
        resolved_path="${resolved_path%.git}"
    elif [[ "$input" == git@* ]]; then
        resolved_path="${input#*:}"
        resolved_path="${resolved_path%.git}"
    elif [[ "$input" == *"/"* ]]; then
        # Full path format: contains /
        resolved_path="$input"
    fi

    # For URL, SSH, and full-path inputs: validate the repo exists
    if [ -n "$resolved_path" ]; then
        log "Validating repository '$resolved_path'..."
        if ! validate_repo "$resolved_path"; then
            return 1
        fi
        echo "$resolved_path"
        return 0
    fi

    # Short name: search via API
    log "Resolving project name '$input'..."
    local search_result
    local search_err
    if ! search_result=$(glab_api --method GET "projects?search=$input&per_page=5" 2>/dev/null); then
        json_error "Failed to search for project '$input'" "$input" ""
        return 1
    fi

    local match
    match=$(echo "$search_result" | jq -r --arg name "$input" \
        '[.[] | select(.path == $name)] | if length == 1 then .[0].path_with_namespace elif length == 0 then "NO_MATCH" else "MULTIPLE" end')

    case "$match" in
        NO_MATCH)
            local candidates
            candidates=$(echo "$search_result" | jq -r '.[].path_with_namespace' 2>/dev/null || echo "none")
            json_error "No exact match for project '$input'. Candidates: $candidates" "$input" ""
            return 1
            ;;
        MULTIPLE)
            local candidates
            candidates=$(echo "$search_result" | jq -r --arg name "$input" \
                '[.[] | select(.path == $name)] | .[].path_with_namespace' 2>/dev/null)
            json_error "Multiple projects match '$input': $candidates" "$input" ""
            return 1
            ;;
        *)
            log "Resolved to: $match"
            echo "$match"
            return 0
            ;;
    esac
}

# --- Branch operations ---

check_branch_exists() {
    local encoded_repo="$1"
    local encoded_branch="$2"
    glab_api --method GET "projects/$encoded_repo/repository/branches/$encoded_branch" &>/dev/null
}

create_branch() {
    local encoded_repo="$1"
    local branch="$2"
    local ref="$3"
    glab_api --method POST "projects/$encoded_repo/repository/branches" \
        -f "branch=$branch" -f "ref=$ref" 2>/dev/null
}

check_branch_protected() {
    local encoded_repo="$1"
    local encoded_branch="$2"
    glab_api --method GET "projects/$encoded_repo/protected_branches/$encoded_branch" 2>/dev/null
}

protect_branch() {
    local encoded_repo="$1"
    local branch="$2"

    local args=(-f "name=$branch")
    local i
    for i in $(seq 0 $((${#RULE_KEYS[@]} - 1))); do
        args+=(-f "${RULE_KEYS[$i]}=${RULE_VALS[$i]}")
    done

    glab_api --method POST "projects/$encoded_repo/protected_branches" "${args[@]}" 2>/dev/null
}

# Extract a rule value from GitLab protected branch API response.
# Handles nested access_levels arrays (e.g. push_access_levels[0].access_level)
# and flat fields (e.g. allow_force_push).
extract_protection_value() {
    local json="$1"
    local key="$2"

    if [[ "$key" == *_access_level ]]; then
        # Nested: push_access_level → .push_access_levels[0].access_level
        local plural="${key%_access_level}_access_levels"
        echo "$json" | jq -r \
            --arg plural "$plural" \
            --arg key "$key" \
            'if (.[$plural] | type) == "array" and (.[$plural] | length) > 0
             then .[$plural][0].access_level | tostring
             elif has($key) then .[$key] | tostring
             else "" end' 2>/dev/null
    else
        echo "$json" | jq -r \
            --arg key "$key" \
            'if has($key) then .[$key] | tostring else "" end' 2>/dev/null
    fi
}

# Compare current protection with requested rules
compare_protection() {
    local current_json="$1"

    local i
    for i in $(seq 0 $((${#RULE_KEYS[@]} - 1))); do
        local key="${RULE_KEYS[$i]}"
        local requested="${RULE_VALS[$i]}"
        local current
        current=$(extract_protection_value "$current_json" "$key")

        if [[ "$current" != "$requested" ]]; then
            return 1
        fi
    done
    return 0
}

# --- Output ---

output_success() {
    local repo="$1"
    local branch="$2"
    local ref="$3"
    local branch_created="$4"
    local protection_applied="$5"
    local protection_already_existed="${6:-false}"

    local rules_json
    rules_json=$(build_rules_json)

    if [ "$HUMAN_OUTPUT" = true ]; then
        echo "=== Branch Operation Complete ==="
        echo "Repository:  $repo"
        echo "Branch:      $branch"
        echo "Source ref:  $ref"
        echo ""
        if [ "$branch_created" = true ]; then
            echo "Branch created: yes"
        else
            echo "Branch created: no (already existed)"
        fi
        if [ "$protection_applied" = true ]; then
            echo "Protection applied: yes"
        elif [ "$protection_already_existed" = true ]; then
            echo "Protection applied: no (already protected with matching rules)"
        fi
        echo ""
        echo "Protection rules:"
        local i
        for i in $(seq 0 $((${#RULE_KEYS[@]} - 1))); do
            printf "  %-35s %s\n" "${RULE_KEYS[$i]}:" "${RULE_VALS[$i]}"
        done
    else
        jq -n \
            --arg repo "$repo" \
            --arg branch "$branch" \
            --arg ref "$ref" \
            --argjson branch_created "$branch_created" \
            --argjson protection_applied "$protection_applied" \
            --argjson protection_already_existed "$protection_already_existed" \
            --argjson rules "$rules_json" \
            '{
                repository: $repo,
                branch: $branch,
                ref: $ref,
                branch_created: $branch_created,
                protection_applied: $protection_applied,
                protection_already_existed: $protection_already_existed,
                protection_rules: $rules
            }'
    fi
}

# --- Main ---

main() {
    local repo_input=""
    local branch_name=""
    local ref=""
    GITLAB_HOST="gitlab.com"
    HUMAN_OUTPUT=false
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --push-level)
                rule_set push_access_level "$2"
                shift 2
                ;;
            --merge-level)
                rule_set merge_access_level "$2"
                shift 2
                ;;
            --unprotect-level)
                rule_set unprotect_access_level "$2"
                shift 2
                ;;
            --allow-force-push)
                rule_set allow_force_push "true"
                shift
                ;;
            --code-owner-approval)
                rule_set code_owner_approval_required "true"
                shift
                ;;
            --rule)
                local key="${2%%=*}"
                local val="${2#*=}"
                rule_set "$key" "$val"
                shift 2
                ;;
            --gitlab-host)
                GITLAB_HOST="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --human-readable)
                HUMAN_OUTPUT=true
                shift
                ;;
            -*)
                log "Unknown option: $1"
                show_usage >&2
                exit 1
                ;;
            *)
                if [ -z "$repo_input" ]; then
                    repo_input="$1"
                elif [ -z "$branch_name" ]; then
                    branch_name="$1"
                elif [ -z "$ref" ]; then
                    ref="$1"
                else
                    log "Unexpected argument: $1"
                    show_usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    check_deps

    if [ -z "$repo_input" ] || [ -z "$branch_name" ] || [ -z "$ref" ]; then
        log "Error: <repo>, <branch-name>, and <ref> are all required."
        show_usage >&2
        exit 1
    fi

    local repo
    if ! repo=$(resolve_repo "$repo_input"); then
        # resolve_repo outputs JSON error to stdout, which was captured
        # Output it now to actual stdout
        echo "$repo"
        exit 1
    fi

    local encoded_repo
    encoded_repo=$(url_encode "$repo")
    local encoded_branch
    encoded_branch=$(url_encode "$branch_name")

    # Dry run
    if [ "$dry_run" = true ]; then
        local rules_json
        rules_json=$(build_rules_json)
        if [ "$HUMAN_OUTPUT" = true ]; then
            echo "=== Dry Run ==="
            echo "Would create branch '$branch_name' from '$ref' on '$repo'"
            echo "Would apply protection rules:"
            local i
            for i in $(seq 0 $((${#RULE_KEYS[@]} - 1))); do
                printf "  %-35s %s\n" "${RULE_KEYS[$i]}:" "${RULE_VALS[$i]}"
            done
        else
            jq -n \
                --arg repo "$repo" \
                --arg branch "$branch_name" \
                --arg ref "$ref" \
                --argjson rules "$rules_json" \
                '{
                    dry_run: true,
                    repository: $repo,
                    branch: $branch,
                    ref: $ref,
                    planned_protection_rules: $rules
                }'
        fi
        exit 0
    fi

    # Step 1: Check if branch exists
    log "Checking if branch '$branch_name' exists..."
    if check_branch_exists "$encoded_repo" "$encoded_branch"; then
        json_error "Branch '$branch_name' already exists" "$repo" "$branch_name"
        exit 1
    fi

    # Step 2: Create branch
    log "Creating branch '$branch_name' from '$ref'..."
    local create_result
    if ! create_result=$(create_branch "$encoded_repo" "$branch_name" "$ref"); then
        json_error "Failed to create branch '$branch_name': $create_result" "$repo" "$branch_name"
        exit 1
    fi

    # Step 3: Check if already protected
    log "Checking branch protection..."
    local protection_json
    if protection_json=$(check_branch_protected "$encoded_repo" "$encoded_branch"); then
        if compare_protection "$protection_json"; then
            log "Branch '$branch_name' is already protected with the requested rules."
            output_success "$repo" "$branch_name" "$ref" true false true
            exit 0
        else
            # Rules differ
            local requested_rules
            requested_rules=$(build_rules_json)
            local actual_rules="{}"
            local i
            for i in $(seq 0 $((${#RULE_KEYS[@]} - 1))); do
                local key="${RULE_KEYS[$i]}"
                local val
                val=$(extract_protection_value "$protection_json" "$key")
                if [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" == "true" ]] || [[ "$val" == "false" ]]; then
                    actual_rules=$(echo "$actual_rules" | jq --arg k "$key" --argjson v "$val" '. + {($k): $v}')
                else
                    actual_rules=$(echo "$actual_rules" | jq --arg k "$key" --arg v "$val" '. + {($k): $v}')
                fi
            done

            jq -n \
                --arg error "Branch '$branch_name' is already protected with different rules" \
                --arg repo "$repo" \
                --arg branch "$branch_name" \
                --argjson current "$actual_rules" \
                --argjson requested "$requested_rules" \
                '{
                    error: $error,
                    repository: $repo,
                    branch: $branch,
                    current_rules: $current,
                    requested_rules: $requested
                }'
            exit 1
        fi
    fi

    # Step 4: Protect branch
    log "Applying protection rules..."
    local protect_result
    if ! protect_result=$(protect_branch "$encoded_repo" "$branch_name"); then
        log "WARNING: Branch '$branch_name' was created but protection failed. The branch exists unprotected — delete it manually if needed."
        json_error "Failed to protect branch '$branch_name' (branch exists unprotected): $protect_result" "$repo" "$branch_name"
        exit 1
    fi

    # Step 5: Output result
    output_success "$repo" "$branch_name" "$ref" true true false
}

main "$@"
