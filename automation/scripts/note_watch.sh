#!/usr/bin/env bash
# note_watch — one changed note, two questions, one model call.
#
# Run by the notes/**/*.md file handler (handlers.yml) once a note has settled.
#   1. Is there a standing instruction in it: something to happen on its own,
#      later, when something occurs ("next time I have a business idea, …")?
#      A new one becomes an automation_propose run.
#   2. Is this note the event an automation you accepted is waiting for
#      (.decree/automations.yml, kind note)? Each one that matches runs on it.
# No model, or an answer that isn't JSON: nothing happens, and the run is still
# done, so saving notes on a stack without a model never fills .decree/attention/.
set -euo pipefail
# shellcheck source=../lib/model.sh
source "${DECREE_LIB}/model.sh"

WS="${AUTOMATIONS_WORKSPACE:-/workspace}"
REGISTRY="${AUTOMATIONS_REGISTRY:-.decree/automations.yml}"
rel="${DECREE_DATA_PATH:?run by the notes file handler, with a path}"

# An automation spec is reconcile's, not an instruction.
case "$rel" in
    notes/automations/*) echo "note_watch: ${rel} is not watched"; exit 0 ;;
esac
[[ -s "${WS}/${rel}" ]] || { echo "note_watch: ${rel} is empty or gone"; exit 0; }
text="$(head -c 6000 "${WS}/${rel}")"

touch "$REGISTRY"
installed="$(yq -o=json '. // []' "$REGISTRY")"
# An automation never triggers on the note that asked for it.
# Only automations whose event is a note; a file or schedule trigger is not ours.
installed="$(jq -c '[.[] | select(.kind == "note")]' <<<"$installed")"
triggers="$(jq -r --arg rel "$rel" '.[] | select(.note != $rel) | "- \(.machine): \(.when)"' <<<"$installed")"

system='You read one note from a person'"'"'s notes and answer two questions about it.
Reply with one JSON object and no other text:
{"instruction": null or {"name": "snake_case_name_for_the_automation", "when": "the event, in plain words", "steps": ["what to do, one step each"]},
 "matches": ["names of automations from the list whose WHEN this note is"]}
instruction: only when the note asks for something to be done automatically on a future
event ("next time…", "whenever…", "every time I…"). A to-do for now, a plan, or a thought
is null. Steps are what the person wants done, in their words, made concrete.
matches: only names from the list given, only when this note clearly is that event.
An empty list when nothing matches or the list is empty.'
user="Automations already accepted (name: when):
${triggers:-none}

The note, ${rel}:
${text}"

if ! reply="$(MODEL_TIMEOUT=180 model_chat "$system" "$user" 800 2>/dev/null)" ||
   ! answer="$(printf '%s' "$reply" | sed '/^```/d' | jq -ce 'select(type == "object")' 2>/dev/null)"; then
    echo "note_watch: no usable answer from the model at $(model_url chat); ${rel} not read"
    exit 0
fi

# 2. Accepted automations this note is the trigger of. Only names the registry
#    has, so a model answer can only start what you accepted.
while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    if jq -e --arg m "$m" --arg rel "$rel" 'any(.[]; .machine == $m and .note != $rel)' <<<"$installed" >/dev/null; then
        decree emit --machine "$m" --param note_path="$rel" </dev/null >/dev/null
        echo "note_watch: ${rel} is the trigger of ${m}; started it"
    fi
done < <(jq -r '.matches // [] | .[] | strings' <<<"$answer")

# 1. A standing instruction, proposed once per note and name.
jq -e '.instruction | type == "object"' <<<"$answer" >/dev/null || exit 0
name="$(jq -r '.instruction.name // ""' <<<"$answer" | tr 'A-Z -' 'a-z__' | tr -cd 'a-z0-9_' | cut -c1-40)"
[[ "$name" =~ ^[a-z][a-z0-9_]{2,}$ ]] || name="automation_$(date +%s)"
when="$(jq -r '.instruction.when // ""' <<<"$answer")"
steps="$(jq -r '.instruction.steps // [] | map("- " + tostring) | join("\n")' <<<"$answer")"
[[ -n "$when" && -n "$steps" ]] || { echo "note_watch: an instruction with no event or no steps; not proposed"; exit 0; }
ledger="${DECREE_STORE}/proposed.tsv"
mkdir -p "$DECREE_STORE"; touch "$ledger"
if grep -qxF "${rel}	${name}" "$ledger"; then
    echo "note_watch: ${rel} already has a proposal for ${name}"
    exit 0
fi
decree emit --machine automation_propose --param note_path="$rel" --param name="$name" \
    --param when="$when" --param steps="$steps" </dev/null >/dev/null
printf '%s\t%s\n' "$rel" "$name" >> "$ledger"
echo "note_watch: ${rel} asks for an automation; proposing ${name}"
