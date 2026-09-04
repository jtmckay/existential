#!/usr/bin/env bash
# rss-poll
#
# Reference example: polls an RSS/Atom feed, filters new items against a
# deterministic regex, and forwards matches into the decree pipeline via the
# outbox. Feed parsing is ../lib/rss.ts (run with tsx); this script owns
# state, filtering, and dedup.
#
# Example cron trigger (automation/cron/rss-poll.md — see
# automation-examples/cron/rss-poll.md for a runnable one):
#
#   ---
#   cron: "*/15 * * * *"
#   routine: rss-poll
#   feed_url: https://github.com/kubernetes/kubernetes/commits/master.atom
#   filter_pattern: "security|CVE|vulnerab"
#   fwd_ntfy_title: RSS match
#   fwd_ntfy_topic: decree
#   ---
#
# First run for a given feed_url only records its current items as seen and
# writes nothing to the outbox — activating this against an established feed
# would otherwise flood chain_routine with its entire backlog. Every run after
# that only evaluates items new since the last run.
#
# chain_routine (default: notify) gets one outbox message per match, plus any
# cron/message fields prefixed fwd_ (prefix stripped) — same forwarding
# convention as gmail-sync.
set -euo pipefail

message_file="${message_file:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v jq  >/dev/null 2>&1 || precheck_fail "rss-poll" "jq not found"
    command -v tsx >/dev/null 2>&1 || precheck_fail "rss-poll" "tsx not found"
    precheck_pass "rss-poll"
    exit 0
fi

# ── Custom params ─────────────────────────────────────────────────────────────

feed_url="${feed_url:-}"
filter_pattern="${filter_pattern:-}"
chain_routine="${chain_routine:-notify}"

[ -n "$feed_url" ]       || { echo "Missing feed_url param."; exit 1; }
[ -n "$filter_pattern" ] || { echo "Missing filter_pattern param."; exit 1; }

# ── State ─────────────────────────────────────────────────────────────────────
# One seen-file per feed_url, keyed by a slug (mirrors gmail-sync's per-label
# history_id.<slug> naming) so multiple feeds/crons never collide.

STATE_DIR="${STATE_DIR:-/data/rss-poll}"
mkdir -p "$STATE_DIR"
_slug=$(printf '%s' "$feed_url" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/_*$//')
SEEN_FILE="${STATE_DIR}/${_slug}.seen"

# ── Fetch ─────────────────────────────────────────────────────────────────────

items=$(FEED_URL="$feed_url" tsx "$(dirname "${BASH_SOURCE[0]}")/../lib/rss.ts")

if [ -z "$items" ]; then
    echo "Feed returned no items: ${feed_url}"
    exit 0
fi

# ── First run: baseline only, no outbox writes ────────────────────────────────

if [ ! -f "$SEEN_FILE" ]; then
    printf '%s\n' "$items" | jq -r '.guid' > "${SEEN_FILE}.tmp"
    mv "${SEEN_FILE}.tmp" "$SEEN_FILE"
    _count=$(wc -l < "$SEEN_FILE" | tr -d ' ')
    echo "First run for ${feed_url} — recorded ${_count} item(s) as seen without filtering."
    exit 0
fi

# ── YAML value escaping ───────────────────────────────────────────────────────

yaml_str() { printf '%s' "${1:-}" | tr -d '\r' | tr '\n' ' ' | sed "s/'/''/g"; }

# ── Filter and queue matches ──────────────────────────────────────────────────

OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
_new_guids=""
_matched=0

while IFS= read -r item; do
    [ -n "$item" ] || continue

    guid=$(printf '%s' "$item" | jq -r '.guid')
    grep -qxF "$guid" "$SEEN_FILE" && continue  # already seen this guid

    _new_guids="${_new_guids}${guid}"$'\n'

    title=$(printf '%s' "$item" | jq -r '.title')
    printf '%s' "$title" | grep -qEi "$filter_pattern" || continue  # deterministic filter

    link=$(printf '%s' "$item" | jq -r '.link')
    pubdate=$(printf '%s' "$item" | jq -r '.pubDate')

    mkdir -p "$OUTBOX_DIR"
    outfile="${OUTBOX_DIR}/rss-poll-$(date +%s%N).md"
    {
        printf -- '---\n'
        printf "routine: %s\n" "$chain_routine"
        printf "title: '%s'\n"    "$(yaml_str "$title")"
        printf "link: '%s'\n"     "$(yaml_str "$link")"
        printf "pubdate: '%s'\n"  "$(yaml_str "$pubdate")"
        printf "feed_url: '%s'\n" "$(yaml_str "$feed_url")"
        # Forward any cron/message fields prefixed fwd_ into the chained
        # message (prefix stripped) — same convention gmail-sync uses.
        while IFS='=' read -r key value; do
            printf "%s: '%s'\n" "${key#fwd_}" "$(yaml_str "$value")"
        done < <(env | grep '^fwd_' | sort)
        printf -- '---\n'
        printf '\n%s\n' "$title"
    } > "${outfile}.tmp"
    mv "${outfile}.tmp" "$outfile"

    _matched=$((_matched + 1))
    echo "Queued: ${title}"
done < <(printf '%s\n' "$items")

# Record every item seen this run (matched or not) so it's never re-evaluated.
if [ -n "$_new_guids" ]; then
    printf '%s' "$_new_guids" >> "$SEEN_FILE"
fi

echo "${_matched} new item(s) matched \"${filter_pattern}\"."
