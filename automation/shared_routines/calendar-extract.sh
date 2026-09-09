#!/usr/bin/env bash
# calendar-extract — mirror upcoming (and recently past) Nextcloud Calendar
# events into workspace/ai/calendar/ as plain notes, so OpenViking indexes
# them and hermes can answer "what's on my calendar" the same way it answers
# anything else that lives in workspace/.
#
# Why notes instead of a live CalDAV lookup at query time: OpenViking's MCP
# tool searches an index, not a live API — see note-connect.sh's header for
# why hermes departments can't just "ask" an external service ad hoc. Turning
# each event into a note is what makes calendar content reachable the same
# way everything else in workspace/ is: through search, not a bespoke tool.
#
# One markdown file per event under workspace/ai/calendar/<calendar-slug>/,
# not workspace/<subdir>/: this content is machine-derived from Nextcloud, not
# something you wrote, and workspace/ai/ is the established home for that —
# see openviking-index-dir's cron (workspace/ai/ is deliberately NOT excluded
# from indexing) and workspace-sync.sh (which DOES exclude it from the
# Nextcloud/bucket bisync, precisely so a note pulled *from* Nextcloud never
# gets written back *into* Nextcloud as a "new" file and looped on forever).
#
# Full-mirror semantics, not an append log: every run recomputes exactly which
# events currently fall in [-CALENDAR_EXTRACT_PAST_DAYS, +CALENDAR_EXTRACT_FUTURE_DAYS]
# and deletes any note left over from a previous run whose event no longer
# does — cancelled, deleted, or simply aged out the back of the window. A
# manifest of paths written last time (STATE_DIR/files.tsv) is what makes
# that diff possible without re-querying "what did I write before".
#
# Recurring events: requested via CalDAV's expand (RFC 4791/6321), so a
# weekly meeting comes back as one VEVENT per occurrence in-window, each
# already carrying its own DTSTART — no RRULE math done here. The one
# fallback case (an occurrence the server did NOT expand, still carrying an
# RRULE) is written as a single note describing the series rather than
# guessed at.
#
# Env vars (set via cron frontmatter):
#   CALENDAR_EXTRACT_PAST_DAYS     how far back to include, default 7
#   CALENDAR_EXTRACT_FUTURE_DAYS   how far ahead to include, default 60
#   CALENDAR_EXTRACT_CALENDARS     comma-separated calendar slugs to include
#                                  (default: every calendar the user has,
#                                  e.g. "personal,contact_birthdays")
#   CALENDAR_EXTRACT_TZ            IANA zone for the human-readable "When:"
#                                  line, default UTC (all-day dates are always
#                                  shown in UTC regardless — see caldav.ts)
#
# Env vars (passed through the decree container's compose env):
#   NEXTCLOUD_URL                              default http://nextcloud
#   NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD
set -euo pipefail

message_file="${message_file:-}"; message_id="${message_id:-}"; message_dir="${message_dir:-}"; chain="${chain:-}"; seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "calendar-extract" "curl not found"
    command -v jq   >/dev/null 2>&1 || precheck_fail "calendar-extract" "jq not found"
    command -v tsx  >/dev/null 2>&1 || precheck_fail "calendar-extract" "tsx not found"
    [ -d "${WORKSPACE_DIR:-/workspace}" ] || precheck_fail "calendar-extract" \
        "${WORKSPACE_DIR:-/workspace} does not exist — is workspace/ mounted?"
    [ -n "${NEXTCLOUD_ADMIN_USER:-}" ]     || precheck_fail "calendar-extract" "NEXTCLOUD_ADMIN_USER is empty — enable nextcloud"
    [ -n "${NEXTCLOUD_ADMIN_PASSWORD:-}" ] || precheck_fail "calendar-extract" "NEXTCLOUD_ADMIN_PASSWORD is empty — enable nextcloud"
    precheck_pass "calendar-extract"
    exit 0
fi

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
STATE_DIR="${STATE_DIR:-/data/calendar-extract}"
OUT_ROOT="${WORKSPACE_DIR}/ai/calendar"
MANIFEST="${STATE_DIR}/files.tsv"
mkdir -p "${STATE_DIR}" "${OUT_ROOT}"
touch "${MANIFEST}"

# ── Fetch ─────────────────────────────────────────────────────────────────────
# caldav.ts reads CALENDAR_EXTRACT_* / NEXTCLOUD_* straight from the
# environment already exported into this process — nothing to pass on argv.

_events_file=$(mktemp)
trap 'rm -f "${_events_file}"' EXIT
if ! tsx "$(dirname "${BASH_SOURCE[0]}")/../lib/caldav.ts" > "${_events_file}"; then
    echo "caldav.ts failed — see output above" >&2
    exit 1
fi

if [ ! -s "${_events_file}" ]; then
    echo "No calendars (or no events in the configured window)."
fi

# ── Markdown escaping for the YAML frontmatter values below ──────────────────

yaml_str() { printf '%s' "${1:-}" | tr -d '\r' | tr '\n' ' ' | sed "s/'/''/g"; }

# ── Write one note per event, tracking what THIS run wrote ────────────────────

_new_manifest=$(mktemp)
_written=0 _skipped=0

while IFS= read -r event; do
    [ -n "$event" ] || continue

    status=$(printf '%s' "$event" | jq -r '.status')
    if [ "$status" = "CANCELLED" ]; then
        _skipped=$((_skipped + 1))
        continue
    fi

    cal_slug=$(printf '%s' "$event" | jq -r '.calendarSlug')
    cal_name=$(printf '%s' "$event" | jq -r '.calendarName')
    uid=$(printf '%s' "$event" | jq -r '.uid')
    summary=$(printf '%s' "$event" | jq -r '.summary')
    description=$(printf '%s' "$event" | jq -r '.description')
    location=$(printf '%s' "$event" | jq -r '.location')
    start=$(printf '%s' "$event" | jq -r '.start')
    end=$(printf '%s' "$event" | jq -r '.end')
    all_day=$(printf '%s' "$event" | jq -r '.allDay')
    recurring=$(printf '%s' "$event" | jq -r '.recurring')
    rrule=$(printf '%s' "$event" | jq -r '.rrule')
    when_text=$(printf '%s' "$event" | jq -r '.whenText')

    [ -n "$cal_slug" ] && [ -n "$uid" ] || { _skipped=$((_skipped + 1)); continue; }

    date_prefix="${start%%T*}"
    title_slug=$(printf '%s' "$summary" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-60)
    uid8=$(printf '%s' "$uid" | sha256sum | cut -c1-8)
    rel_dir="ai/calendar/${cal_slug}"
    rel_path="${rel_dir}/${date_prefix}-${title_slug:-event}-${uid8}.md"
    mkdir -p "${WORKSPACE_DIR}/${rel_dir}"

    {
        printf -- '---\n'
        printf "calendar: '%s'\n"  "$(yaml_str "$cal_name")"
        printf "uid: '%s'\n"       "$(yaml_str "$uid")"
        printf "start: '%s'\n"     "$(yaml_str "$start")"
        printf "end: '%s'\n"       "$(yaml_str "$end")"
        printf "all_day: %s\n"     "${all_day}"
        [ -n "$location" ] && printf "location: '%s'\n" "$(yaml_str "$location")"
        printf -- '---\n\n'
        printf '# %s\n\n' "$summary"
        printf '**When:** %s\n' "$when_text"
        printf '**Calendar:** %s\n' "$cal_name"
        [ -n "$location" ] && printf '**Location:** %s\n' "$location"
        if [ "$recurring" = "true" ] && [ -n "$rrule" ]; then
            printf '**Repeats:** %s (server did not expand this occurrence)\n' "$rrule"
        fi
        if [ -n "$description" ]; then
            printf '\n%s\n' "$description"
        fi
    } > "${WORKSPACE_DIR}/${rel_path}.tmp"
    mv "${WORKSPACE_DIR}/${rel_path}.tmp" "${WORKSPACE_DIR}/${rel_path}"

    printf '%s\n' "$rel_path" >> "${_new_manifest}"
    _written=$((_written + 1))
done < "${_events_file}"

# ── Remove notes for events no longer in the window (aged out, cancelled, deleted) ──

_removed=0
if [ -s "${MANIFEST}" ]; then
    while IFS= read -r old_rel; do
        [ -n "$old_rel" ] || continue
        grep -qxF "$old_rel" "${_new_manifest}" 2>/dev/null && continue
        rm -f "${WORKSPACE_DIR}/${old_rel}"
        _removed=$((_removed + 1))
    done < "${MANIFEST}"
fi

sort -o "${_new_manifest}" "${_new_manifest}"
mv "${_new_manifest}" "${MANIFEST}"

echo "calendar-extract: ${_written} note(s) written, ${_skipped} skipped (cancelled/malformed), ${_removed} removed (out of window)."
