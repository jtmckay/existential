#!/usr/bin/env bash
# idea-workup — fan one flagged idea out to the departments that can answer it.
#
# An alternative to note-develop as TRIAGE_ROUTINE. Where note-develop makes one
# call and writes one document, this makes none of its own: it writes three
# outbox messages, each naming the department whose hermes profile owns the
# tools that question needs.
#
#   who else is doing this   → research  (the only department with web access)
#   how big is the market    → research
#   what is my value prop    → sales     (pricing and positioning)
#
# Each answer lands in workspace/ai/<slug>-<question>.md as its own document
# with its own notification, which is the point — three focused answers you can
# read separately beat one long report nobody finishes.
#
# Chained by note-triage (routine: idea-workup, note_path: <relative path>), or
# run by hand against any note.
#
# Two things worth knowing before enabling it:
#
#   * The departments write to /workspace/ai, and only the MAIN decree daemon
#     has a writable /workspace. Enable idea-workup and hermes-dept in
#     services/decree/decree/config.yml — not in decree-backup.
#   * The profiles must exist. hermes' entrypoint provisions them from
#     ai/hermes/profiles/ on boot, so this is only a question after adding a
#     new department: restart hermes. Without a profile every department call
#     401s, because each carries its own API_SERVER_KEY rather than borrowing
#     the default one's.
#
# Decree runs messages one at a time and AGENT_TIMEOUT defaults to 900s, so a
# fan-out of three can take the better part of an hour. It is not stuck.
#
# Manual invocation:
#   docker exec decree decree run --routine idea-workup \
#     --param note_path=ideas/tool-rental.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v jq >/dev/null 2>&1 || precheck_fail "idea-workup" "jq not found"
    [ -d "${NOTES_DIR:-/data/notes}" ] || precheck_fail "idea-workup" \
        "NOTES_DIR ${NOTES_DIR:-/data/notes} does not exist — run the 'notes' routine first, or point NOTES_DIR at your vault"
    [ -n "${HERMES_API_KEY:-}" ] || precheck_fail "idea-workup" \
        "HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through"
    [ -f "${SCRIPT_DIR}/hermes-dept.sh" ] || precheck_fail "idea-workup" \
        "hermes-dept.sh not found in shared_routines/ — nothing to hand the questions to"
    precheck_pass "idea-workup"
    exit 0
fi

note_path="${note_path:-}"
note_reason="${note_reason:-}"
NOTES_DIR="${NOTES_DIR:-/data/notes}"
WORKUP_MAX_CHARS="${WORKUP_MAX_CHARS:-6000}"

# --- Implementation ---

OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
# decree reads the outbox but never creates it — an absent dir is silently
# treated as "no messages", so the whole fan-out would vanish without an error.
mkdir -p "$OUTBOX_DIR"

if [ -z "$note_path" ]; then
    echo "note_path is required (relative to ${NOTES_DIR})" >&2
    exit 1
fi

src="${NOTES_DIR}/${note_path}"
if [ ! -f "$src" ]; then
    echo "Note not found: ${src}" >&2
    exit 1
fi

note_body="$(head -c "$WORKUP_MAX_CHARS" "$src")"

# A stable, filesystem-safe stem for the three answers.
slug="$(basename "$note_path")"
slug="${slug%.md}"
slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
slug="${slug:-idea}"

echo "Working up: ${note_path}"
if [ -n "$note_reason" ]; then
    echo "Flagged as: ${note_reason}"
fi

# --- The three questions ---------------------------------------------------
#
# Each is one outbox message. The shape is what hermes-dept expects: it strips
# the frontmatter and treats the body as the task, so the question and the note
# both go below the fence. The note is embedded rather than referenced because a
# department profile has no filesystem access.

hand_off() {
    # hand_off <profile> <suffix> <question>
    local profile="$1" suffix="$2" question="$3" out

    out="${OUTBOX_DIR}/idea-workup-${suffix}-$(date +%s%N).md"
    {
        printf -- '---\n'
        printf 'routine: hermes-dept\n'
        printf 'profile: %s\n' "$profile"
        printf 'output_name: %s\n' "$(jq -rn --arg v "${slug}-${suffix}" '$v|@json')"
        printf 'source_file: %s\n' "$(jq -rn --arg v "$note_path" '$v|@json')"
        printf -- '---\n\n'
        printf '%s\n\n' "$question"
        if [ -n "$note_reason" ]; then
            printf 'Flagged during triage as: %s\n\n' "$note_reason"
        fi
        printf -- '--- the note ---\n%s\n--- end note ---\n' "$note_body"
    } > "$out"

    echo "  ${profile} → workspace/ai/${slug}-${suffix}.md"
}

hand_off research competition \
"Who is already doing this? Name the real products and companies that solve this problem
today, what they charge, and where each of them is weak. Then say in one paragraph whether
the space is crowded, contested, or genuinely open. Where you could not find something, say
so rather than filling the gap."

hand_off research tam \
"How big is the market for this? Work from the bottom up: who exactly would buy it, roughly
how many of them there are, and what they already spend on the problem. Show the arithmetic
so the number can be argued with. State every assumption you had to make, and say plainly
which of them you could not verify."

hand_off sales value-prop \
"What is the value proposition here? Name who the buyer is, then write the one sentence that
would make that buyer stop and read, then the three reasons they would choose this over what
they use today, then the strongest objection they would raise and whether it can be answered.
Finish with a pricing shape — not a number, the shape — and why it fits how they already buy."

echo "Queued 3 questions for ${slug}."
