#!/usr/bin/env bash
# note-triage — watch the notes vault and flag the notes worth acting on.
#
# Scans NOTES_DIR for notes that are new or changed since the last run, asks the
# model one cheap yes/no question per note, and chains TRIAGE_ROUTINE for the
# ones that pass. Most notes are a grocery list — being stingy here is the point.
#
# The judgment lives in TRIAGE_CRITERIA, which is meant to be rewritten. Ships
# looking for a business idea; change it to look for whatever you actually want
# chased down.
#
# A note that passes is then checked against the ledger of ideas already
# evaluated (STATE_DIR/ideas.tsv) — the same idea written down a second time is
# one idea, not two, and only genuinely new ones chain any work. Set
# TRIAGE_LEDGER=false to chain every pass instead.
#
# First run is a no-op by design: it records the vault as seen without triaging,
# so enabling this on an existing vault does not fire a thousand model calls.
# Set TRIAGE_BOOTSTRAP=true for one run if you do want the backlog scanned.
#
# Manual invocation — decree has no `run` subcommand; drop a message instead:
#   printf -- '---\nroutine: note-triage\n---\n' > automation/inbox/note-triage.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "note-triage" "curl not found"
    command -v jq   >/dev/null 2>&1 || precheck_fail "note-triage" "jq not found"
    [ -d "${NOTES_DIR:-/data/notes}" ] || precheck_fail "note-triage" \
        "NOTES_DIR ${NOTES_DIR:-/data/notes} does not exist — run the 'notes' routine first, or point NOTES_DIR at your vault"
    _key="${TRIAGE_API_KEY:-${HERMES_API_KEY:-}}"
    _auth=()
    if [ -n "$_key" ]; then _auth=(-H "Authorization: Bearer ${_key}"); fi
    curl -fsS --max-time 10 -o /dev/null \
        "${TRIAGE_API_URL:-http://hermes-agent:8642/v1}/models" \
        "${_auth[@]}" 2>/dev/null \
        || precheck_fail "note-triage" \
        "gateway unreachable at ${TRIAGE_API_URL:-http://hermes-agent:8642/v1} — is hermes-agent up? (set TRIAGE_API_URL=http://ollama:11434/v1 to use Ollama directly)"
    precheck_pass "note-triage"
    exit 0
fi

NOTES_DIR="${NOTES_DIR:-/data/notes}"
STATE_DIR="${STATE_DIR:-/data/note-triage}"
TRIAGE_API_URL="${TRIAGE_API_URL:-http://hermes-agent:8642/v1}"
TRIAGE_MODEL="${TRIAGE_MODEL:-}"
TRIAGE_ROUTINE="${TRIAGE_ROUTINE:-note-develop}"
TRIAGE_CRITERIA="${TRIAGE_CRITERIA:-a business idea — something the author could plausibly build, sell, or start}"
TRIAGE_MAX_NOTES="${TRIAGE_MAX_NOTES:-20}"
TRIAGE_MAX_CHARS="${TRIAGE_MAX_CHARS:-6000}"
TRIAGE_MIN_CHARS="${TRIAGE_MIN_CHARS:-120}"
TRIAGE_BOOTSTRAP="${TRIAGE_BOOTSTRAP:-false}"
TRIAGE_TIMEOUT="${TRIAGE_TIMEOUT:-120}"
TRIAGE_DRY_RUN="${TRIAGE_DRY_RUN:-false}"
TRIAGE_API_KEY="${TRIAGE_API_KEY:-}"
TRIAGE_LEDGER="${TRIAGE_LEDGER:-true}"
TRIAGE_LEDGER_MAX="${TRIAGE_LEDGER_MAX:-100}"

# --- Implementation ---

# Byte-wise collation throughout: the manifest is compared with comm, which
# rejects its input if the sort order does not match the ambient locale.
export LC_ALL=C

# Fall back to the gateway key from the container environment.
if [ -z "$TRIAGE_API_KEY" ]; then
    TRIAGE_API_KEY="${HERMES_API_KEY:-}"
fi

OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
MANIFEST="${STATE_DIR}/seen.tsv"
LEDGER="${STATE_DIR}/ideas.tsv"

mkdir -p "$STATE_DIR"
touch "$MANIFEST" "$LEDGER"

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

if [ ! -s "$MANIFEST" ] && [ "$TRIAGE_BOOTSTRAP" != "true" ]; then
    cp "$current" "$MANIFEST"
    echo "First run — recorded ${total} note(s) as seen without triaging."
    echo "Set TRIAGE_BOOTSTRAP=true for one run to scan the existing vault."
    exit 0
fi

# New or changed = lines in current that are not in the manifest verbatim
changed="$(comm -23 "$current" <(sort "$MANIFEST") || true)"

if [ -z "$changed" ]; then
    cp "$current" "$MANIFEST"
    echo "No new or changed notes (${total} tracked)."
    exit 0
fi

changed_count=$(printf '%s\n' "$changed" | grep -c . || true)
echo "${changed_count} new or changed note(s) of ${total} tracked."

# --- Ask the model ---------------------------------------------------------

chat() {
    # chat <system> <user> <max_tokens>  → assistant text on stdout
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
          max_tokens:$mt, temperature:0}
         + (if $model == "" then {} else {model:$model} end)')"

    curl "${args[@]}" -d "$payload" | jq -r '.choices[0].message.content // empty'
}

SYSTEM="You triage personal notes. You are shown one note. Decide whether it contains ${TRIAGE_CRITERIA}.

Be strict. Most notes are not. A passing mention, a link with no thought attached, a task, a
shopping list, meeting minutes, or a journal entry is NOT a match. Only answer YES when the
note contains a genuine, developed-enough thought that acting on it would be useful.

Reply with exactly one line, in this format:
YES: <one sentence naming the idea>
or
NO"

# --- Has this idea already been evaluated? ---------------------------------

LEDGER_SYSTEM="You are given a numbered list of ideas that have already been evaluated, and
one new idea. Decide whether the new idea is materially the same as one already on the list.

The same idea in different words is a duplicate. A different market, a different mechanism,
or a genuinely new application of a similar technology is NOT — say NEW when in doubt.

Reply with exactly one line, either:
NEW
or
DUPLICATE: <the number it matches>"

# ledger_verdict <reason> → exit 0 when the idea is new; exit 1 and print the
# matching prior idea when it is a duplicate.
#
# Fails open on purpose. A missing verdict, an empty ledger or a gateway blip
# all mean "new" — a duplicate workup wastes a run, a dropped one loses the idea
# for good. This is the opposite of the triage verdict above, which fails closed
# by leaving the note unseen so the next run retries it.
ledger_verdict() {
    local reason="$1" list answer n prior

    [ "$TRIAGE_LEDGER" = "true" ] || return 0
    [ -s "$LEDGER" ] || return 0

    list="$(tail -n "$TRIAGE_LEDGER_MAX" "$LEDGER" | cut -f2- | nl -ba -w1 -s': ')"

    answer="$(chat "$LEDGER_SYSTEM" "Already evaluated:
${list}

New idea:
${reason}" 100 || true)"
    answer="$(printf '%s' "$answer" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [ -z "$answer" ]; then
        echo "WARN: no ledger verdict for \"${reason}\" — treating it as new" >&2
        return 0
    fi

    case "$answer" in
        DUPLICATE*|duplicate*)
            n="$(printf '%s' "$answer" | sed 's/[^0-9]*\([0-9][0-9]*\).*/\1/')"
            prior=""
            if [ -n "$n" ]; then
                prior="$(printf '%s\n' "$list" | sed -n "${n}p" | sed 's/^[0-9]*: //')"
            fi
            printf '%s' "${prior:-an earlier idea}"
            return 1
            ;;
    esac

    return 0
}

flagged=0
deduped=0
examined=0

while IFS=$'\t' read -r hash rel; do
    if [ -z "${rel:-}" ]; then continue; fi
    if [ "$examined" -ge "$TRIAGE_MAX_NOTES" ]; then
        echo "Reached TRIAGE_MAX_NOTES (${TRIAGE_MAX_NOTES}) — the rest will be picked up next run."
        break
    fi

    path="${NOTES_DIR}/${rel}"
    [ -f "$path" ] || continue

    body="$(head -c "$TRIAGE_MAX_CHARS" "$path")"
    if [ "${#body}" -lt "$TRIAGE_MIN_CHARS" ]; then
        echo "skip (too short): ${rel}"
        continue
    fi

    examined=$((examined + 1))

    verdict="$(chat "$SYSTEM" "Note path: ${rel}

---
${body}" 200 || true)"

    if [ -z "$verdict" ]; then
        echo "WARN: no verdict for ${rel} — leaving it unseen so the next run retries" >&2
        # Drop it from the manifest update so it is reconsidered next run
        awk -F'\t' -v h="$hash" -v r="$rel" '!($1 == h && $2 == r)' "$current" > "${current}.new" \
            && mv "${current}.new" "$current"
        continue
    fi

    verdict="$(printf '%s' "$verdict" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    case "$verdict" in
        YES*|yes*)
            reason="$(printf '%s' "$verdict" | sed 's/^[Yy][Ee][Ss][[:space:]]*:\?[[:space:]]*//')"

            # Is it new? An idea rewritten in a second note is still one idea.
            if ! prior="$(ledger_verdict "$reason")"; then
                echo "dup   ${rel} — already evaluated: ${prior}"
                deduped=$((deduped + 1))
                continue
            fi

            echo "FLAG  ${rel} — ${reason}"
            flagged=$((flagged + 1))

            if [ "$TRIAGE_DRY_RUN" = "true" ]; then
                continue
            fi

            # Record it before chaining, so a crash mid-chain cannot produce the
            # same workup twice on the next run.
            printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$reason" >> "$LEDGER"

            out="${OUTBOX_DIR}/note-triage-$(date +%s%N).md"
            {
                printf -- '---\n'
                printf 'routine: %s\n' "$TRIAGE_ROUTINE"
                printf 'note_path: %s\n' "$(jq -rn --arg v "$rel" '$v|@json')"
                printf 'note_reason: %s\n' "$(jq -rn --arg v "$reason" '$v|@json')"
                printf -- '---\n\n'
                printf '%s\n' "$reason"
            } > "$out"
            ;;
        *)
            echo "pass  ${rel}"
            ;;
    esac
done <<< "$changed"

cp "$current" "$MANIFEST"

echo "Examined ${examined}, flagged ${flagged}, already known ${deduped}."
