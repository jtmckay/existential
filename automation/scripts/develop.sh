#!/usr/bin/env bash
# develop — build one automation from its migration.
#
# The migration (notes/automations/<name>.md, filed by reconcile) says what is
# true once the automation exists. Claude (lib/agent.sh) reads it when this
# container is signed in, the chat model when not, and answers with the trigger,
# as one JSON line, and the `steps` function; this writes the rest from fixed
# templates:
#   .decree/machines/<name>.yml   one state, invoking its script, emitting notify
#   .decree/scripts/<name>.sh     lib/automations/run.sh + steps + automation_run
#   the trigger                   note: an entry note_watch matches notes against
#                                 file: a .decree/handlers.yml entry
#                                 cron: .decree/cron/<name>.md
# The gate is decree check plus the trigger's own rules. A failed gate is undone
# and its errors kept for the second attempt; the second failure ends the run,
# which reaches your phone like any failed run.
set -euo pipefail
# shellcheck source=../lib/model.sh
source "${DECREE_LIB}/model.sh"
# shellcheck source=../lib/automations/registry.sh
source "${DECREE_LIB}/automations/registry.sh"
# shellcheck source=../lib/firecrawl.sh
source "${DECREE_LIB}/firecrawl.sh"
# shellcheck source=../lib/agent.sh
source "${DECREE_LIB}/agent.sh"

name="${DECREE_DATA_AUTOMATION:?the migration names no automation}" from="${DECREE_DATA_FROM:-}"
[[ "$name" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || { echo "develop: '${name}' is not a machine name" >&2; exit 1; }
if [[ -e ".decree/machines/${name}.yml" ]] && ! automation_installed "$name"; then
    echo "develop: ${name} is a machine this stack ships or you wrote; refusing to replace it" >&2; exit 1
fi
spec="$(awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{f=0; next} !f' "$DECREE_MESSAGE")"
errors="${DECREE_RUN_DIR}/gate.err"

system='You build one automation from its spec. Reply with exactly two parts and nothing else:
Line 1: TRIGGER: <one JSON object>, one of
  {"kind": "note", "when": "the kind of note of theirs that is the event, in plain words"}
  {"kind": "file", "match": "a glob relative to the workspace", "changes": ["created"], "quiet": 30}
  {"kind": "cron", "cron": "minute hour day-of-month month day-of-week"}
Then the bash function, starting "steps() {", no fences.
steps runs under set -euo pipefail. It has $NOTE_PATH and $NOTE (the note or file that
started it; empty on a schedule), ask "<instructions>" "<input>" (prints one answer from a
language model), curl and jq. It prints its results as Markdown, one "## " heading per
step. A step needing the person becomes a "## For you" item. It never writes or deletes
files, never reads /secrets, never sends data anywhere but ask, agent and public read-only APIs.
A file trigger never matches ai/, .decree/ or notes/automations/.'
if firecrawl_on; then system+='
It can read the web: web_search "<query>" [n] prints the top n results (default 5), each
page'"'"'s text in a <source url="..."> tag, and web_read <url> prints one page. Search several angles, then
give ask the sources with an instruction to use only them, say so when there are none, and cite each claim'"'"'s URL:
    sources="$(web_search "<query>" 5; web_search "<another angle>" 5)"
    echo "## <step>"; ask "<instructions>. Use only the sources below; cite URLs." "$NOTE

$sources"
A step whose answer the person will act on (build it or not, buy it or not) comes first,
as "## Verdict", so it is what reaches their phone.'
else system+='
There is no web search: a step that needs the web says, in "## For you", where to look.'
fi
if agent_ready; then system+='
For a step that has to look through the person'"'"'s files or reason at length, agent "<task>" prints
the answer of Claude Code, which can read and search the workspace but changes nothing.'
fi
user="The spec:
${spec}"
[[ -s "$errors" ]] && user+="

Your last answer failed these checks; fix them:
$(cat "$errors")"

if agent_ready; then
    reply="$(agent "${system}

${user}" | sed '/^```/d')" || { echo "develop: no answer from Claude" >&2; exit 1; }
else
    reply="$(MODEL_TIMEOUT=300 model_chat "$system" "$user" 2500 | sed '/^```/d')" || { echo "develop: no answer from the model" >&2; exit 1; }
fi
trigger="$(sed -n 's/^TRIGGER: *//p' <<<"$reply" | head -1)"
# From "steps() {" to its closing "}", so a word after the function is no part of it.
code="$(awk '/^steps\(\) *\{/{f=1} f{print} f && /^}$/{exit}' <<<"$reply")"

# ── The gate, before anything is written ─────────────────────────────────────
fails=()
kind="$(jq -r '.kind // ""' <<<"$trigger" 2>/dev/null || true)"
case "$kind" in
    note) [[ -n "$(jq -r '.when // ""' <<<"$trigger")" ]] || fails+=("a note trigger needs 'when'") ;;
    file) match="$(jq -r '.match // ""' <<<"$trigger")"
          [[ -n "$match" ]] || fails+=("a file trigger needs 'match'")
          [[ "$match" == ai/* || "$match" == .decree/* || "$match" == notes/automations/* || "$match" == '**'* ]] &&
              fails+=("the file trigger '${match}' would match its own output or decree's files")
          jq -e '(.changes // ["created"]) - ["created","modified","deleted"] | length == 0' <<<"$trigger" >/dev/null ||
              fails+=("changes must be created, modified or deleted") ;;
    cron) [[ "$(jq -r '.cron // ""' <<<"$trigger" | wc -w)" == 5 ]] || fails+=("a cron trigger needs five fields") ;;
    *)    fails+=("line 1 must be TRIGGER: with kind note, file or cron (got: ${trigger:-nothing})") ;;
esac
if [[ "$code" != steps\(\)* ]]; then fails+=("no steps() function after the TRIGGER line")
elif ! err="$(bash -n <<<"$code" 2>&1)"; then fails+=("the steps function does not parse: ${err}"); fi
firecrawl_on || ! grep -qE '\bweb_(search|read)\b' <<<"$code" || fails+=("web_search and web_read need Firecrawl, which is off")
agent_ready || ! grep -qE '\bagent\b' <<<"$code" || fails+=("agent needs Claude signed in here, and it is not")
fail_gate() {
    printf -- '- %s\n' "${fails[@]}" > "$errors"
    echo "develop: ${name} failed the gate:" >&2; cat "$errors" >&2
    exit 1
}
[[ ${#fails[@]} -eq 0 ]] || fail_gate

# ── Install, keeping what was there so a failed check puts it back ───────────
backup="${DECREE_RUN_DIR}/previous"; rm -rf "$backup"; mkdir -p "$backup"
touched=(".decree/machines/${name}.yml" ".decree/scripts/${name}.sh" ".decree/cron/${name}.md" "$REGISTRY" "$HANDLERS" "$WATCH")
for f in "${touched[@]}"; do [[ -e "$f" ]] && cp -p "$f" "$backup/$(echo "$f" | tr / _)"; done
restore() {
    for f in "${touched[@]}"; do
        if [[ -e "$backup/$(echo "$f" | tr / _)" ]]; then cp -p "$backup/$(echo "$f" | tr / _)" "$f"; else rm -f "$f"; fi
    done
}
touch "$REGISTRY"
automation_remove "$name"            # a rebuild starts from nothing

cat > ".decree/machines/${name}.yml" <<YML
# Built by develop from notes/automations/${name}.md. Edit that file, not this one.
name: ${name}
description: $(jq -Rn --arg d "$(sed -n 's/^# //p' <<<"$spec" | head -1)" '$d')
data:
  note_path: { type: string, default: "" }
  path: { type: string, default: "" }
  change: { type: string, default: "" }
initial: run
states:
  run:
    invoke: ${name}
    transitions: { done: done }
    emits: [notify]
  done: { final: true }
  failed: { final: true }
YML
{
    printf '#!/usr/bin/env bash\n# Built by develop from notes/automations/%s.md. Edit that file, not this one.\n' "$name"
    printf '# shellcheck source=../lib/automations/run.sh\nsource "${DECREE_LIB}/automations/run.sh"\n\n'
    printf '%s\n\nautomation_run %s\n' "$code" "$name"
} > ".decree/scripts/${name}.sh"
chmod 755 ".decree/scripts/${name}.sh"

entry="$(jq -c --arg m "$name" --arg n "$from" --arg s "notes/automations/${name}.md" '{machine: $m} + . + {note: $n, spec: $s}' <<<"$trigger")"
case "$kind" in
    note) yq -i ".states.watch.emits = ((.states.watch.emits // []) + [\"${name}\"] | unique)" "$WATCH" ;;
    file) touch "$HANDLERS"
          yq -i ". = ((. // []) + [$(jq -c --arg m "$name" '{match: .match, machine: $m, changes: (.changes // ["created"]), quiet: (.quiet // 30)}' <<<"$trigger")])" "$HANDLERS" ;;
    cron) mkdir -p .decree/cron
          printf -- '---\ncron: "%s"\nmachine: %s\n---\n\nBuilt by develop from notes/automations/%s.md.\n' \
              "$(jq -r .cron <<<"$trigger")" "$name" "$name" > ".decree/cron/${name}.md" ;;
esac
yq -i ". = ((. // []) + [${entry}])" "$REGISTRY"

if ! check="$(decree check --no-color 2>&1)"; then
    restore
    fails=("decree check: $( { grep -i "$name" <<<"$check" || printf '%s\n' "$check"; } | head -5 | paste -sd ';')")
    fail_gate
fi
rm -f "$errors"

# ── Record: what was built from, so reconcile can tell an edit from no change ─
migration="$(cd .decree/migrations && ls -- A*-"${name}".md 2>/dev/null | head -1 || true)"
if [[ -n "$migration" ]]; then mkdir -p .decree/applied; cp ".decree/migrations/${migration}" ".decree/applied/${migration}"; fi
case "$kind" in
    note) starts="when you write a note that is: $(jq -r .when <<<"$trigger")" ;;
    file) starts="when a file matching $(jq -r .match <<<"$trigger") changes" ;;
    cron) starts="on the schedule $(jq -r .cron <<<"$trigger")" ;;
esac
echo "develop: built ${name}, which starts ${starts}"
printf '%s starts %s. Results go to ai/automations/%s/.\n' "$name" "$starts" "$name" |
    decree emit --machine notify --param ntfy_title="Automation built" --param ntfy_tags=robot >/dev/null
