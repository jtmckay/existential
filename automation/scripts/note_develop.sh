#!/usr/bin/env bash
# note_develop — take one flagged note and do the work that can be done without you.
#
# Emitted by note_triage (note_path: <relative path>), or run by hand against
# any note. Produces a single markdown file: what it found,
# a draft plan, and — the part that matters — the questions it could not answer
# without you.
#
# With Firecrawl enabled it searches the web before drafting (lib/firecrawl.sh).
# Without it, it says so in the output rather than inventing a market.
#
# Output is written locally and, when NOTE_OUTPUT_RCLONE_DEST is set, copied
# back beside the original note. It is NOT written into NOTES_DIR — that path is
# an rclone sync cache and anything left there is deleted on the next sync.
#
# By hand:
#   docker exec automation decree emit --machine note_develop \
#     --param note_path=ideas/tool-rental.md </dev/null

set -euo pipefail

note_path="$DECREE_DATA_NOTE_PATH"
note_reason="$DECREE_DATA_NOTE_REASON"
NOTES_DIR="${NOTES_DIR:-/data/notes}"
OUTPUT_DIR="${OUTPUT_DIR:-/data/note-triage/output}"
export MODEL_TIMEOUT="${MODEL_TIMEOUT:-300}"
export MODEL_TEMPERATURE=0.2
NOTE_OUTPUT_SUFFIX="${NOTE_OUTPUT_SUFFIX:-.plan.md}"
NOTE_OUTPUT_RCLONE_DEST="${NOTE_OUTPUT_RCLONE_DEST:-}"
NOTE_NOTIFY="${NOTE_NOTIFY:-true}"

# --- Implementation ---

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

# shellcheck source=../lib/model.sh
source "${DECREE_LIB}/model.sh"
# shellcheck source=../lib/firecrawl.sh
source "${DECREE_LIB}/firecrawl.sh"

# --- Optional: web research ------------------------------------------------

research=""
if firecrawl_on; then
    echo "Researching via Firecrawl..."
    query="$(model_chat \
        "Write a single web search query that would find existing products or companies doing what this note describes. Reply with the query text only, no quotes, no explanation." \
        "$note_body" 100 || true)"
    query="$(printf '%s' "$query" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [ -n "$query" ]; then
        echo "  query: ${query}"
        research="$(web_search "$query" 5 || true)"
    fi

    if [ -n "$research" ]; then
        echo "  found $(printf '%s' "$research" | grep -c '^<source ' || true) result(s)"
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
draft="$(model_chat "$SYSTEM" "$USER" 2000)"

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
    decree emit --machine notify --param ntfy_title="Idea developed — ${note_name}" \
        --param ntfy_priority=default --param ntfy_tags=bulb >/dev/null <<EOF
${note_reason:-A note was flagged and developed.}

${questions}
EOF
fi
