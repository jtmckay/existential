#!/usr/bin/env bash
# note-connect — watch your knowledge base for connections to what you already know.
#
# Scans NOTES_DIR for notes that are new or changed since the last run, hands each one to a
# hermes department with OpenViking access, and asks for the single most interesting,
# non-obvious connection to something already there. Only a self-scored connection at or
# above CONNECT_MIN_SCORE is written down and sent to you — most notes do not have one
# waiting.
#
# NOTES_DIR defaults to /workspace — the same tree OpenViking already indexes and Hermes
# already reads — precisely so this needs nothing beyond Hermes and OpenViking to work.
# Point it at /data/notes instead to scan a note-triage-style vault mirror there.
#
# Different job from note-triage: triage asks "is this worth acting on" and is stingy on
# purpose because most notes are a grocery list. This asks a narrower question of every new
# or changed note instead — "does anything you already know actually connect to this, in a
# way you would not have thought of yourself" — and is just as stingy about the answer. A
# topical match ("both mention coffee") does not clear the bar; a real connection does.
#
# The search itself needs OpenViking, which is a tool, not a plain completion — so this
# routine hands the note to a hermes department profile that carries `mcp: openviking`
# (CONNECT_PROFILE, default "research", see ai/hermes/profiles/research/profile.yml) rather
# than calling the gateway's default profile the way note-triage does. The department
# searches the OpenViking index, proposes at most one connection with a self-scored
# interestingness, and this routine only acts when that score clears CONNECT_MIN_SCORE.
#
# A connection that clears the bar is written to OUTPUT_DIR (and, when
# CONNECT_OUTPUT_RCLONE_DEST is set, copied beside the source note too) and a notification
# goes out — the notification alone carries the full insight, so there is nothing else to
# check for this to be useful out of the box. The same source-note-to-target pairing is never
# surfaced twice — CONNECT_LEDGER remembers what has already been shown.
#
# First run is a no-op by design, same reason as note-triage: it records the tree as seen
# without scanning, so turning this on over an existing knowledge base does not fire a call
# per note. Set CONNECT_BOOTSTRAP=true for one run to scan the backlog.
#
# Manual invocation — decree has no `run` subcommand; drop a message instead:
#   printf -- '---\nroutine: note-connect\n---\n' > automation/inbox/note-connect.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/hermes.sh
source "${SCRIPT_DIR}/../lib/hermes.sh"

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "note-connect" "curl not found"
    command -v jq   >/dev/null 2>&1 || precheck_fail "note-connect" "jq not found"
    [ -d "${NOTES_DIR:-/workspace}" ] || precheck_fail "note-connect" \
        "NOTES_DIR ${NOTES_DIR:-/workspace} does not exist — is /workspace mounted? Or point NOTES_DIR at a vault of your own"
    _key="${CONNECT_API_KEY:-${HERMES_API_KEY:-}}"
    [ -n "$_key" ] || precheck_fail "note-connect" \
        "HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through"
    _profile="${CONNECT_PROFILE:-research}"
    _url="$(hermes_profile_url "$_profile")"
    curl -fsS --max-time 10 -o /dev/null -H "Authorization: Bearer ${_key}" \
        "${_url}/models" 2>/dev/null \
        || precheck_fail "note-connect" \
        "profile '${_profile}' unreachable at ${_url} — is hermes-agent up, and does ai/hermes/profiles/${_profile}/ exist? A profile added after hermes-agent last started needs a restart."
    precheck_pass "note-connect"
    exit 0
fi

NOTES_DIR="${NOTES_DIR:-/workspace}"
STATE_DIR="${STATE_DIR:-/data/note-connect}"
OUTPUT_DIR="${OUTPUT_DIR:-/data/note-connect/output}"
CONNECT_PROFILE="${CONNECT_PROFILE:-research}"
CONNECT_MODEL="${CONNECT_MODEL:-}"
CONNECT_MAX_NOTES="${CONNECT_MAX_NOTES:-20}"
CONNECT_MAX_CHARS="${CONNECT_MAX_CHARS:-6000}"
CONNECT_MIN_CHARS="${CONNECT_MIN_CHARS:-120}"
CONNECT_MIN_SCORE="${CONNECT_MIN_SCORE:-7}"
CONNECT_BOOTSTRAP="${CONNECT_BOOTSTRAP:-false}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-300}"
CONNECT_DRY_RUN="${CONNECT_DRY_RUN:-false}"
CONNECT_API_KEY="${CONNECT_API_KEY:-}"
CONNECT_LEDGER="${CONNECT_LEDGER:-true}"
CONNECT_NOTIFY="${CONNECT_NOTIFY:-true}"
CONNECT_OUTPUT_RCLONE_DEST="${CONNECT_OUTPUT_RCLONE_DEST:-}"

# --- Implementation ---

# Byte-wise collation throughout: the manifest is compared with comm, which
# rejects its input if the sort order does not match the ambient locale.
export LC_ALL=C

if [ -z "$CONNECT_API_KEY" ]; then
    CONNECT_API_KEY="${HERMES_API_KEY:-}"
fi

OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
RCLONE_CONF="${RCLONE_CONF:-/secrets/rclone/rclone.conf}"
MANIFEST="${STATE_DIR}/seen.tsv"
LEDGER="${STATE_DIR}/connections.tsv"

mkdir -p "$STATE_DIR"
touch "$MANIFEST" "$LEDGER"

# The department call. Every other routine that talks to hermes owns its own
# curl; this one is the same shape as hermes-dept's, aimed at a profile instead
# of the default gateway, because finding a connection means searching the
# vault — a tool call, not a plain completion.
HERMES_API_URL="$(hermes_profile_url "$CONNECT_PROFILE")"
HERMES_TIMEOUT="$CONNECT_TIMEOUT"
HERMES_API_KEY="$CONNECT_API_KEY"
HERMES_MODEL="$CONNECT_MODEL"
export HERMES_API_URL HERMES_TIMEOUT HERMES_API_KEY HERMES_MODEL

# Build the current view of the vault: "<sha256>\t<relative path>"
current="$(mktemp)"
trap 'rm -f "$current" "${current}.new" 2>/dev/null || true' EXIT

find "$NOTES_DIR" -type f -name '*.md' \
    -not -path '*/.obsidian/*' \
    -not -path '*/.trash/*' \
    -not -path '*/.git/*' \
    -print0 2>/dev/null \
| while IFS= read -r -d '' f; do
    printf '%s\t%s\n' "$(sha256sum "$f" | awk '{print $1}')" "${f#"$NOTES_DIR"/}"
done | sort > "$current"

total=$(wc -l < "$current")

if [ ! -s "$MANIFEST" ] && [ "$CONNECT_BOOTSTRAP" != "true" ]; then
    cp "$current" "$MANIFEST"
    echo "First run — recorded ${total} note(s) as seen without scanning for connections."
    echo "Set CONNECT_BOOTSTRAP=true for one run to scan the existing vault."
    exit 0
fi

changed="$(comm -23 "$current" <(sort "$MANIFEST") || true)"

if [ -z "$changed" ]; then
    cp "$current" "$MANIFEST"
    echo "No new or changed notes (${total} tracked)."
    exit 0
fi

changed_count=$(printf '%s\n' "$changed" | grep -c . || true)
echo "${changed_count} new or changed note(s) of ${total} tracked."

SYSTEM="You are shown one personal note. Search the knowledge base available to you for the
single existing note or resource that connects to it in the most interesting, non-obvious way
— not the most similar one. A shared topic, project, or person is not enough on its own; the
connection has to produce an insight the author would not have made by just remembering this
note existed.

Be strict. If searching turns up nothing better than a topical match, or nothing at all, say
so plainly — most notes do not have one of these waiting for them.

Reply with exactly this shape, and nothing else:

CONNECTION: <the vault path or title of the other note>
INSIGHT: <one or two sentences — what the connection is, and why it is worth noticing>
SCORE: <1-10, how genuinely interesting and non-obvious this is; 10 means the author would be
glad someone pointed it out>

or, if nothing clears the bar, reply with exactly:

NONE"

examined=0
surfaced=0
deduped=0

while IFS=$'\t' read -r hash rel; do
    if [ -z "${rel:-}" ]; then continue; fi
    if [ "$examined" -ge "$CONNECT_MAX_NOTES" ]; then
        echo "Reached CONNECT_MAX_NOTES (${CONNECT_MAX_NOTES}) — the rest will be picked up next run."
        break
    fi

    path="${NOTES_DIR}/${rel}"
    [ -f "$path" ] || continue

    body="$(head -c "$CONNECT_MAX_CHARS" "$path")"
    if [ "${#body}" -lt "$CONNECT_MIN_CHARS" ]; then
        echo "skip (too short): ${rel}"
        continue
    fi

    examined=$((examined + 1))

    answer="$(hermes_chat "$SYSTEM" "Note path: ${rel}

---
${body}" 300 || true)"

    if [ -z "$answer" ]; then
        echo "WARN: no answer for ${rel} — leaving it unseen so the next run retries" >&2
        awk -F'\t' -v h="$hash" -v r="$rel" '!($1 == h && $2 == r)' "$current" > "${current}.new" \
            && mv "${current}.new" "$current"
        continue
    fi

    if printf '%s\n' "$answer" | grep -qi '^NONE\b'; then
        echo "pass  ${rel}"
        continue
    fi

    target="$(printf '%s\n' "$answer" | grep -m1 -i '^CONNECTION:' | sed 's/^[Cc][Oo][Nn][Nn][Ee][Cc][Tt][Ii][Oo][Nn]:[[:space:]]*//')"
    insight="$(printf '%s\n' "$answer" | grep -m1 -i '^INSIGHT:' | sed 's/^[Ii][Nn][Ss][Ii][Gg][Hh][Tt]:[[:space:]]*//')"
    score="$(printf '%s\n' "$answer" | grep -m1 -i '^SCORE:' | sed 's/[^0-9]*\([0-9][0-9]*\).*/\1/')"

    if [ -z "$target" ] || [ -z "$score" ]; then
        echo "WARN: unparseable answer for ${rel} — leaving it unseen so the next run retries" >&2
        echo "  ${answer}" >&2
        awk -F'\t' -v h="$hash" -v r="$rel" '!($1 == h && $2 == r)' "$current" > "${current}.new" \
            && mv "${current}.new" "$current"
        continue
    fi

    if [ "$score" -lt "$CONNECT_MIN_SCORE" ]; then
        echo "pass  ${rel} — found ${target} but scored ${score}/10, below CONNECT_MIN_SCORE (${CONNECT_MIN_SCORE})"
        continue
    fi

    if [ "$CONNECT_LEDGER" = "true" ] && grep -qF -- "$(printf '%s\t%s' "$rel" "$target")" "$LEDGER"; then
        echo "dup   ${rel} <-> ${target} — already surfaced"
        deduped=$((deduped + 1))
        continue
    fi

    echo "FOUND ${rel} <-> ${target} (${score}/10) — ${insight}"

    if [ "$CONNECT_DRY_RUN" = "true" ]; then
        continue
    fi

    # Record before writing, so a crash mid-write cannot surface the same
    # pairing twice on the next run.
    printf '%s\t%s\n' "$rel" "$target" >> "$LEDGER"
    surfaced=$((surfaced + 1))

    note_name="$(basename "$rel")"
    mkdir -p "$OUTPUT_DIR/$(dirname "$rel")"
    out_rel="${rel}.connection.md"
    out_local="${OUTPUT_DIR}/${out_rel}"

    {
        printf -- '---\n'
        printf 'generated_by: note-connect\n'
        printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'source_note: %s\n' "$(jq -rn --arg v "$rel" '$v|@json')"
        printf 'connected_to: %s\n' "$(jq -rn --arg v "$target" '$v|@json')"
        printf 'score: %s\n' "$score"
        printf -- '---\n\n'
        printf '## A connection worth noticing\n\n'
        printf '**%s** connects to **%s**:\n\n' "$note_name" "$target"
        printf '%s\n' "$insight"
    } > "$out_local"

    echo "Wrote ${out_local}"

    if [ -n "$CONNECT_OUTPUT_RCLONE_DEST" ]; then
        if [ -f "$RCLONE_CONF" ] && command -v rclone >/dev/null 2>&1; then
            rclone copyto --config "$RCLONE_CONF" \
                "$out_local" "${CONNECT_OUTPUT_RCLONE_DEST%/}/${out_rel}"
        else
            echo "WARN: CONNECT_OUTPUT_RCLONE_DEST set but rclone or ${RCLONE_CONF} is missing" >&2
        fi
    fi

    if [ "$CONNECT_NOTIFY" = "true" ]; then
        mkdir -p "$OUTBOX_DIR"
        cat > "${OUTBOX_DIR}/note-connect-$(date +%s%N).md" << EOF
---
routine: notify
ntfy_title: $(jq -rn --arg v "Connection found — ${note_name}" '$v|@json')
ntfy_priority: default
ntfy_tags: link
---
${insight}

${note_name} <-> ${target}
EOF
    fi
done <<< "$changed"

cp "$current" "$MANIFEST"

echo "Examined ${examined}, surfaced ${surfaced}, already known ${deduped}."
