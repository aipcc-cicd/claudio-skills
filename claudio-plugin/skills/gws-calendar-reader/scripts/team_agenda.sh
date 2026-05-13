#!/usr/bin/env bash
#
# Show upcoming calendar events for team members.
#
# Reads team members from /output/gws-calendar-reader/team.json by default.
# Requires that team members have shared their calendar with the authenticated user.
#
# Usage:
#   ./team_agenda.sh [OPTIONS]
#
# Options:
#   --email EMAIL        Show agenda for one person only (use 'me' for your own)
#   --days N             Number of days ahead (default: 1 = today)
#   --timezone TZ        IANA timezone override
#   --human              Human-readable output (default: JSON)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_FILE="$SCRIPT_DIR/../team.json"

EMAIL_FILTER=""
DAYS=1
TZ_OVERRIDE=""
HUMAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "ERROR: --email requires a value" >&2; exit 1; }
            EMAIL_FILTER="$2"; shift 2 ;;
        --days)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "ERROR: --days requires a numeric value" >&2; exit 1; }
            [[ "$2" =~ ^[0-9]+$ ]] || { echo "ERROR: --days must be a positive integer" >&2; exit 1; }
            DAYS="$2"; shift 2 ;;
        --timezone)
            [[ -z "${2:-}" || "${2:-}" == --* ]] && { echo "ERROR: --timezone requires a TZ name" >&2; exit 1; }
            TZ_OVERRIDE="$2"; shift 2 ;;
        --human)    HUMAN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ============================================================================
# LOAD TEAM
# ============================================================================

if [ -n "$EMAIL_FILTER" ]; then
    if [ "$EMAIL_FILTER" = "me" ]; then
        TEAM_EMAILS=("primary")
        TEAM_NAMES=("me")
    else
        TEAM_EMAILS=("$EMAIL_FILTER")
        TEAM_NAMES=("$EMAIL_FILTER")
    fi
    TIMEZONE="${TZ_OVERRIDE:-UTC}"
else
    if [ ! -f "$TEAM_FILE" ]; then
        echo "ERROR: team.json not found at $TEAM_FILE — copy team.json.example to team.json and fill in your team members" >&2
        exit 1
    fi
    TEAM=$(cat "$TEAM_FILE")
    mapfile -t TEAM_EMAILS < <(echo "$TEAM" | jq -r '.team[].email')
    mapfile -t TEAM_NAMES  < <(echo "$TEAM" | jq -r '.team[].name')
    TIMEZONE="${TZ_OVERRIDE:-$(echo "$TEAM" | jq -r '.timezone // "UTC"')}"
fi

# ============================================================================
# BUILD TIME WINDOW
# ============================================================================

TIME_MIN=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIME_MAX=$(TZ="$TIMEZONE" date -d "+${DAYS} days 23:59:59" -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Fetching agenda from $TIME_MIN to $TIME_MAX..." >&2

# ============================================================================
# FETCH EVENTS PER PERSON
# ============================================================================

ALL_AGENDAS="[]"

for i in "${!TEAM_EMAILS[@]}"; do
    email="${TEAM_EMAILS[$i]}"
    name="${TEAM_NAMES[$i]}"

    echo "  → $name ($email)" >&2

    PARAMS=$(jq -n \
        --arg cal  "$email" \
        --arg tmin "$TIME_MIN" \
        --arg tmax "$TIME_MAX" \
        --arg tz   "$TIMEZONE" \
        '{calendarId: $cal, timeMin: $tmin, timeMax: $tmax, timeZone: $tz,
          singleEvents: true, orderBy: "startTime",
          fields: "items(id,summary,start,end,attendees,status,eventType)"}')

    RAW=$(gws calendar events list --params "$PARAMS") || {
        echo "    WARNING: could not fetch calendar for $email (not shared or no access)" >&2
        continue
    }

    EVENTS=$(echo "$RAW" | jq --arg name "$name" --arg email "$email" '{
        name: $name,
        email: $email,
        events: [.items[]? | {
            summary: (.summary // "(no title)"),
            start: (.start.dateTime // .start.date),
            end: (.end.dateTime // .end.date),
            eventType: (.eventType // "default"),
            status: (.status // "confirmed")
        }]
    }')

    ALL_AGENDAS=$(echo "$ALL_AGENDAS" | jq --argjson e "$EVENTS" '. + [$e]')
done

# ============================================================================
# OUTPUT
# ============================================================================

if [ "$HUMAN" = true ]; then
    echo ""
    echo "=== Team Agenda: next $DAYS day(s) ==="
    echo "$ALL_AGENDAS" | jq -r '.[] |
        "── \(.name) (\(.email)) ──",
        (if (.events | length) == 0 then
            "   (no events)"
        else
            (.events[] | "   \(.start)  \(.summary)")
        end),
        ""'
else
    jq -n \
        --argjson agendas "$ALL_AGENDAS" \
        --arg tmin "$TIME_MIN" \
        --arg tmax "$TIME_MAX" \
        '{window: {from: $tmin, to: $tmax}, team: $agendas}'
fi
