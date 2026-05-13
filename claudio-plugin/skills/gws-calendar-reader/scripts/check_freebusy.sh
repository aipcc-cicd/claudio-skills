#!/usr/bin/env bash
#
# Check free/busy status for team members over a time window.
#
# Reads team members from /output/gws-calendar-reader/team.json by default.
#
# Usage:
#   ./check_freebusy.sh [OPTIONS]
#
# Options:
#   --emails EMAIL,...   Comma-separated emails (overrides team.json)
#   --hours N            Next N hours from now (default: 8)
#   --today              Rest of today
#   --date YYYY-MM-DD    Full day on that date
#   --timezone TZ        IANA timezone (default: from team.json or UTC)
#   --human              Human-readable output (default: JSON)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_FILE="$SCRIPT_DIR/../team.json"

EMAILS_OVERRIDE=""
HOURS=""
USE_TODAY=false
DATE_OVERRIDE=""
TZ_OVERRIDE=""
HUMAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --emails)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "ERROR: --emails requires a value" >&2; exit 1; }
            EMAILS_OVERRIDE="$2"; shift 2 ;;
        --hours)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "ERROR: --hours requires a numeric value" >&2; exit 1; }
            [[ "$2" =~ ^[0-9]+$ ]] || { echo "ERROR: --hours must be a positive integer" >&2; exit 1; }
            HOURS="$2"; shift 2 ;;
        --today)    USE_TODAY=true; shift ;;
        --date)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "ERROR: --date requires YYYY-MM-DD" >&2; exit 1; }
            [[ "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "ERROR: --date must be YYYY-MM-DD" >&2; exit 1; }
            DATE_OVERRIDE="$2"; shift 2 ;;
        --timezone)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "ERROR: --timezone requires a TZ name" >&2; exit 1; }
            TZ_OVERRIDE="$2"; shift 2 ;;
        --human)    HUMAN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ============================================================================
# LOAD TEAM CONFIG
# ============================================================================

if [ -n "$EMAILS_OVERRIDE" ]; then
    EMAILS_JSON=$(echo "$EMAILS_OVERRIDE" | tr ',' '\n' | jq -R '{"id": .}' | jq -s '.')
    NAMES_MAP=$(echo "$EMAILS_OVERRIDE" | tr ',' '\n' | jq -R '{(.): .}' | jq -s 'add')
    TIMEZONE="${TZ_OVERRIDE:-UTC}"
else
    if [ ! -f "$TEAM_FILE" ]; then
        echo "ERROR: team.json not found at $TEAM_FILE — copy team.json.example to team.json and fill in your team members" >&2
        exit 1
    fi
    TEAM=$(cat "$TEAM_FILE")
    EMAILS_JSON=$(echo "$TEAM" | jq '[.team[] | {"id": .email}]')
    NAMES_MAP=$(echo "$TEAM" | jq '[.team[] | {(.email): .name}] | add')
    TIMEZONE="${TZ_OVERRIDE:-$(echo "$TEAM" | jq -r '.timezone // "UTC"')}"
fi

# ============================================================================
# BUILD TIME WINDOW
# ============================================================================

if [ -n "$DATE_OVERRIDE" ]; then
    # Convert local midnight/end-of-day in the resolved timezone to UTC
    TIME_MIN=$(TZ="$TIMEZONE" date -d "${DATE_OVERRIDE} 00:00:00" -u +"%Y-%m-%dT%H:%M:%SZ")
    TIME_MAX=$(TZ="$TIMEZONE" date -d "${DATE_OVERRIDE} 23:59:59" -u +"%Y-%m-%dT%H:%M:%SZ")
elif [ "$USE_TODAY" = true ]; then
    TIME_MIN=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TIME_MAX=$(TZ="$TIMEZONE" date -d "today 23:59:59" -u +"%Y-%m-%dT%H:%M:%SZ")
elif [ -n "$HOURS" ]; then
    TIME_MIN=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TIME_MAX=$(date -u -d "+${HOURS} hours" +"%Y-%m-%dT%H:%M:%SZ")
else
    TIME_MIN=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TIME_MAX=$(date -u -d "+8 hours" +"%Y-%m-%dT%H:%M:%SZ")
fi

echo "Checking free/busy from $TIME_MIN to $TIME_MAX..." >&2

# ============================================================================
# QUERY FREEBUSY API
# ============================================================================

REQUEST=$(jq -n \
    --arg tmin "$TIME_MIN" \
    --arg tmax "$TIME_MAX" \
    --arg tz   "$TIMEZONE" \
    --argjson items "$EMAILS_JSON" \
    '{timeMin: $tmin, timeMax: $tmax, timeZone: $tz, items: $items}')

RAW=$(gws calendar freebusy query --json "$REQUEST")

# ============================================================================
# FORMAT OUTPUT
# ============================================================================

if [ "$HUMAN" = true ]; then
    echo ""
    echo "=== Team Free/Busy: $TIME_MIN → $TIME_MAX ==="
    echo ""
    echo "$RAW" | jq -r --argjson names "$NAMES_MAP" '
        .calendars | to_entries[] |
        (.key) as $email |
        ($names[$email] // $email) as $name |
        (.value.busy // []) as $busy |
        if ($busy | length) == 0 then
            "  ✓ FREE    \($name) (\($email))"
        else
            "  ✗ BUSY    \($name) (\($email))\n" +
            ($busy | map("             " + .start + " → " + .end) | join("\n"))
        end
    '
    echo ""
else
    echo "$RAW" | jq --argjson names "$NAMES_MAP" '{
        window: {from: .timeMin, to: .timeMax},
        members: [
            .calendars | to_entries[] |
            (.key) as $email |
            {
                email: $email,
                name: ($names[$email] // $email),
                status: (if (.value.busy // [] | length) == 0 then "free" else "busy" end),
                busy_intervals: (.value.busy // [])
            }
        ]
    }'
fi
