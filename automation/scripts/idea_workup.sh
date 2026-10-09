#!/usr/bin/env bash
# idea_workup — fan one flagged idea out to the departments that can answer it.
#
# An alternative to note_develop as TRIAGE_ROUTINE. Where note_develop makes one
# call and writes one document, this makes none of its own: it emits three
# agent_task messages, each on the department whose hermes profile owns the
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
# Emitted by note_triage (note_path: <relative path>), or run by hand against
# any note.
#
# The profiles must exist. hermes' entrypoint provisions them from
#     ai/hermes/profiles/ on boot, so this is only a question after adding a
#     new department: restart hermes. Without a profile every department call
#     401s, because each carries its own API_SERVER_KEY rather than borrowing
#     the default one's.
#
# Decree runs messages one at a time and AGENT_TIMEOUT defaults to 900s, so a
# fan-out of three can take the better part of an hour. It is not stuck.
#
# By hand:
#   docker exec automation decree emit --machine idea_workup \
#       --param note_path=ideas/tool-rental.md </dev/null

set -euo pipefail

note_path="$DECREE_DATA_NOTE_PATH"
note_reason="$DECREE_DATA_NOTE_REASON"
NOTES_DIR="${NOTES_DIR:-/data/notes}"
WORKUP_MAX_CHARS="${WORKUP_MAX_CHARS:-6000}"

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
# Each is one agent_task message on its department's profile, the question and
# the note as its body. The note is embedded rather than referenced because a
# department profile has no filesystem access.

hand_off() {
    # hand_off <profile> <suffix> <question>
    local profile="$1" suffix="$2" question="$3"
    {
        printf '%s\n\n' "$question"
        if [ -n "$note_reason" ]; then
            printf 'Flagged during triage as: %s\n\n' "$note_reason"
        fi
        printf -- '--- the note ---\n%s\n--- end note ---\n' "$note_body"
    } | decree emit --machine agent_task --param profile="$profile" \
            --param output_name="${slug}-${suffix}" >/dev/null

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
