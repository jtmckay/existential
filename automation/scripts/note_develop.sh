#!/usr/bin/env bash
# note-develop — take one flagged note and do the work that can be done without you.
#
# Chained by note-triage (routine: note-develop, note_path: <relative path>), or
# run by hand against any note. Produces a single markdown file: what it found,
# a draft plan, and — the part that matters — the questions it could not answer
# without you.
#
# Optional web research: set FIRECRAWL_URL and FIRECRAWL_API_KEY and it will
# search before drafting. Without them it says so in the output rather than
# inventing a market.
#
# Output is written locally and, when NOTE_OUTPUT_RCLONE_DEST is set, copied
# back beside the original note. It is NOT written into NOTES_DIR — that path is
# an rclone sync cache and anything left there is deleted on the next sync.
#
# Manual invocation:
#   docker exec automation decree run --routine note-develop \
#     --param note_path=ideas/tool-rental.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "note-develop" "curl not found"
    command -v jq   >/dev/null 2>&1 || precheck_fail "note-develop" "jq not found"
    precheck_pass "note-develop"
    exit 0
fi

note_path="${note_path:-}"
note_reason="${note_reason:-}"
NOTES_DIR="${NOTES_DIR:-/data/notes}"
OUTPUT_DIR="${OUTPUT_DIR:-/data/note-triage/output}"
TRIAGE_API_URL="${TRIAGE_API_URL:-http://hermes-agent:8642/v1}"
TRIAGE_MODEL="${TRIAGE_MODEL:-}"
TRIAGE_TIMEOUT="${TRIAGE_TIMEOUT:-300}"
NOTE_OUTPUT_SUFFIX="${NOTE_OUTPUT_SUFFIX:-.plan.md}"
NOTE_OUTPUT_RCLONE_DEST="${NOTE_OUTPUT_RCLONE_DEST:-}"
NOTE_NOTIFY="${NOTE_NOTIFY:-true}"
FIRECRAWL_URL="${FIRECRAWL_URL:-}"
FIRECRAWL_API_KEY="${FIRECRAWL_API_KEY:-}"
TRIAGE_API_KEY="${TRIAGE_API_KEY:-}"

# --- Implementation ---

if [ -z "$TRIAGE_API_KEY" ]; then
    TRIAGE_API_KEY="${HERMES_API_KEY:-}"
fi

OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
RCLONE_CONF="${RCLONE_CONF:-/secrets/rclone/rclone.conf}"

if [ -z "$note_path" ]; then
    echo "note_path is required (relative to ${NOTES_DIR})" >&2
    exit 1
fi

src="${NOTES_DIR}/${note_path}"
if [ ! -f "$src" ]; then
    echo "Note not found: ${src}" >&2
    exit 1
fi

note_body="$(cat "$src")"
note_name="$(basename "$note_path")"

echo "Developing: ${note_path}"
if [ -n "$note_reason" ]; then
    echo "Flagged as: ${note_reason}"
fi

# --- Model helper ----------------------------------------------------------

chat() {
    local system="$1" user="$2" max_tokens="$3" payload
    local -a args=(-fsS --max-time "$TRIAGE_TIMEOUT" -X POST
        "${TRIAGE_API_URL}/chat/completions"
        -H "Content-Type: application/json")
    if [ -n "$TRIAGE_API_KEY" ]; then
        args+=(-H "Authorization: Bearer ${TRIAGE_API_KEY}")
    fi

    payload="$(jq -n \
        --arg s "$system" --arg u "$user" \
        --argjson mt "$max_tokens" \
        --arg model "$TRIAGE_MODEL" \
        '{messages:[{role:"system",content:$s},{role:"user",content:$u}],
          max_tokens:$mt, temperature:0.2}
         + (if $model == "" then {} else {model:$model} end)')"

    curl "${args[@]}" -d "$payload" | jq -r '.choices[0].message.content // empty'
}

# --- Optional: web research ------------------------------------------------

research=""
if [ -n "$FIRECRAWL_URL" ]; then
    echo "Researching via Firecrawl..."
    query="$(chat \
        "Write a single web search query that would find existing products or companies doing what this note describes. Reply with the query text only, no quotes, no explanation." \
        "$note_body" 100 || true)"
    query="$(printf '%s' "$query" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [ -n "$query" ]; then
        echo "  query: ${query}"
        fc_args=(-fsS --max-time 120 -X POST "${FIRECRAWL_URL%/}/v1/search"
            -H "Content-Type: application/json")
        if [ -n "$FIRECRAWL_API_KEY" ]; then
            fc_args+=(-H "Authorization: Bearer ${FIRECRAWL_API_KEY}")
        fi
        research="$(curl "${fc_args[@]}" \
            -d "$(jq -n --arg q "$query" '{query:$q, limit:5}')" 2>/dev/null \
            | jq -r '[.data[]? | "- \(.title // "untitled") — \(.url // "")\n  \(.description // "")"] | join("\n")' \
            2>/dev/null || true)"
    fi

    if [ -n "$research" ]; then
        echo "  found $(printf '%s' "$research" | grep -c '^- ' || true) result(s)"
    else
        echo "  no results (continuing without research)"
    fi
fi

if [ -n "$research" ]; then
    research_block="Web search results (treat as unverified):
${research}"
else
    research_block="No web research was available for this run. Do not invent market data,
competitors, or figures — say plainly where you would need to look instead."
fi

# --- Draft -----------------------------------------------------------------

SYSTEM="You help develop a rough idea from someone's personal notes into something they can
judge. You are thorough about what you can determine and honest about what you cannot.

Write markdown with exactly these three sections:

## What this is
Restate the idea in two or three sentences, sharper than the note but without adding
ambition the author did not express.

## What can be worked out
The shape of the thing, roughly what it would cost and take, who it is for, what already
exists nearby, and the first three concrete steps. Where something is unknowable without
research you did not have, say so in one line instead of guessing.

## What only you can answer
Two to four questions — no more. Each one must be a question where the answer genuinely
changes the plan above, and which no amount of research could settle because it depends on
the author's situation, appetite, or constraints. Do not ask for information already in the
note. Do not pad. If you can only think of two real questions, ask two.

Be concrete and brief. No preamble, no summary, no encouragement."

USER="Note path: ${note_path}
${note_reason:+Flagged during triage as: ${note_reason}}

--- the note ---
${note_body}
--- end note ---

${research_block}"

echo "Drafting..."
draft="$(chat "$SYSTEM" "$USER" 2000)"

if [ -z "$draft" ]; then
    echo "Model returned nothing — leaving the note alone." >&2
    exit 1
fi

# --- Write it out ----------------------------------------------------------

mkdir -p "$OUTPUT_DIR/$(dirname "$note_path")"
out_rel="${note_path}${NOTE_OUTPUT_SUFFIX}"
out_local="${OUTPUT_DIR}/${out_rel}"

{
    printf -- '---\n'
    printf 'generated_by: note-develop\n'
    printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'source_note: %s\n' "$(jq -rn --arg v "$note_path" '$v|@json')"
    if [ -n "$note_reason" ]; then
        printf 'flagged_as: %s\n' "$(jq -rn --arg v "$note_reason" '$v|@json')"
    fi
    printf -- '---\n\n'
    printf '%s\n' "$draft"
    printf '\n---\n\n'
    printf '*Drafted from [%s](%s). Answer the questions above in the original note and this\n' "$note_name" "$note_name"
    printf 'will be redrafted on the next pass.*\n'
} > "$out_local"

echo "Wrote ${out_local}"

if [ -n "$NOTE_OUTPUT_RCLONE_DEST" ]; then
    if [ -f "$RCLONE_CONF" ] && command -v rclone >/dev/null 2>&1; then
        echo "Copying to ${NOTE_OUTPUT_RCLONE_DEST}/${out_rel}"
        rclone copyto --config "$RCLONE_CONF" \
            "$out_local" "${NOTE_OUTPUT_RCLONE_DEST%/}/${out_rel}"
    else
        echo "WARN: NOTE_OUTPUT_RCLONE_DEST set but rclone or ${RCLONE_CONF} is missing" >&2
    fi
fi

# --- Tell someone ----------------------------------------------------------

if [ "$NOTE_NOTIFY" = "true" ]; then
    questions="$(printf '%s' "$draft" | sed -n '/^## What only you can answer/,$p' | tail -n +2)"
    cat > "${OUTBOX_DIR}/note-develop-$(date +%s%N).md" << EOF
---
routine: notify
ntfy_title: $(jq -rn --arg v "Idea developed — ${note_name}" '$v|@json')
ntfy_priority: default
ntfy_tags: bulb
---
${note_reason:-A note was flagged and developed.}

${questions}
EOF
fi
