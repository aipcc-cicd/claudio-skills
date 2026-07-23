# Check if a package already exists in production repository indexes.
# Sourced by submit.sh — not executed directly.
# Outputs PRODUCTION_WARNING and exits 0 if found.
# Requires: normalize_pep503 from _format.sh

# ---------------------------------------------------------------------------
# Check production repositories for existing package
# ---------------------------------------------------------------------------

check_production_repos() {
    local package_name="$1"
    local base_url="$2"
    local product_versions_csv="$3"
    local variants_csv="$4"

    local normalized
    normalized=$(normalize_pep503 "$package_name")

    IFS=',' read -ra versions <<< "$product_versions_csv"
    IFS=',' read -ra variants <<< "$variants_csv"

    local found_in="[]"
    for pv in "${versions[@]}"; do
        pv=$(echo "$pv" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        for variant in "${variants[@]}"; do
            variant=$(echo "$variant" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local encoded_name
            encoded_name=$(jq -Rr '@uri' <<< "$normalized")
            local url="${base_url}/${pv}/${variant}/simple/${encoded_name}/"
            local http_code
            set +e
            http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null)
            local rc=$?
            set -e
            [[ $rc -ne 0 ]] && continue
            if [[ "$http_code" == "200" ]]; then
                found_in=$(echo "$found_in" | jq --arg pv "$pv" --arg v "$variant" --arg u "$url" \
                    '. + [{"product_version": $pv, "variant": $v, "repo_url": $u}]')
            fi
        done
    done

    local count
    count=$(echo "$found_in" | jq 'length')
    if [[ "$count" -gt 0 ]]; then
        echo "PRODUCTION_WARNING"
        jq -n --arg pkg "$package_name" --argjson found "$found_in" '{
            warning: "production_exists",
            message: "Note: this check does not verify whether the requested extras are available.",
            details: {package_name: $pkg, found_in: $found}
        }'
        exit 0
    fi
}
