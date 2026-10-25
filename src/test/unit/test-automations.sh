#!/usr/bin/env bash
# test-automations.sh — a note asks for an automation; it is proposed as a
# migration, accepted, built by develop, triggered, rebuilt on edit and removed.
# note_watch, automation_propose, reconcile, develop and lib/automations/, with
# the model and `decree` stubbed:
#
#   watch     a standing instruction becomes one automation_propose, once; with no
#             model reachable nothing happens and the run still succeeds
#   propose   the proposal is a develop migration: intent, outcome, constraints,
#             acceptance criteria; an answer missing a section fails the run
#   accept    reconcile files it as a pending migration; a name decree already
#             has is refused
#   develop   builds machine, script and a note trigger; a file trigger becomes a
#             handler, a cron trigger a cron file; a failed gate is undone and its
#             errors are kept for the next attempt
#   web       web_search and web_read return Firecrawl's pages as Markdown; develop
#             tells the model about them only when Firecrawl is on, and refuses
#             steps that use them when it is off
#   trigger   a later note the model matches starts it, and only an accepted one;
#             it researches the web, writes its results and notifies the verdict
#   edit      a changed spec of a built automation is run again
#   remove    deleting the spec removes all of it
#
# Everything is written under a temp dir, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
for _t in node jq yq curl; do
    command -v "$_t" >/dev/null 2>&1 || { echo "skipped — ${_t} not available (run inside existential-adhoc)"; exit 0; }
done

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()    { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has()   { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }
assert_lacks() { if [[ "$2" != *"$3"* ]]; then _ok "$1"; else _fail "$1" "found: $3"; fi; }

TMP="$(mktemp -d)"; STUB_PID=""
trap '[ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

# ── The model (note_watch's question, the code request, `ask` from steps) and
# Firecrawl (/v2/search, /v2/scrape), on one port ──────────────────────────────
cat > "${TMP}/stub.js" <<'JS'
const http = require("node:http"), fs = require("node:fs");
const dir = process.argv[2];
http.createServer((req, res) => {
  let body = ""; req.on("data", (c) => (body += c));
  req.on("end", () => {
    res.setHeader("Content-Type", "application/json");
    if (req.url === "/v2/search") {
      const q = JSON.parse(body).query;
      fs.appendFileSync(`${dir}/searches`, `${q}\n`);
      return res.end(JSON.stringify({ success: true, data: { web: [
        { url: "https://walkies.example/plans", title: "Walkies: dog walking plans",
          description: "Monthly dog walking", markdown: `# Walkies\nMonthly plans from $99, for: ${q}` },
      ] } }));
    }
    if (req.url === "/v2/scrape") return res.end(JSON.stringify({ success: true, data: { markdown: `# Page at ${JSON.parse(body).url}` } }));
    const m = JSON.parse(body || "{}").messages || [];
    const sys = (m[0] && m[0].content) || "", user = (m[1] && m[1].content) || "";
    if (sys.includes("build one automation")) { fs.writeFileSync(`${dir}/build-prompt`, user); fs.writeFileSync(`${dir}/build-system`, sys); }
    const content = sys.includes("answer two questions") ? fs.readFileSync(`${dir}/watch-reply`, "utf8")
      : sys.includes("You write a decree migration") ? fs.readFileSync(`${dir}/spec-reply`, "utf8")
      : sys.includes("build one automation") ? fs.readFileSync(`${dir}/build-reply`, "utf8")
      : `ANSWER to ${sys.slice(0, 20)} about ${user.split("\n")[0].slice(0, 40)}${user.includes("walkies.example") ? ", citing walkies.example" : ""}`;
    res.end(JSON.stringify({ choices: [{ message: { content } }] }));
  });
}).listen(0, "127.0.0.1", function () { fs.writeFileSync(`${dir}/port`, String(this.address().port)); });
JS
node "${TMP}/stub.js" "$TMP" & STUB_PID=$!
for _ in $(seq 50); do [[ -s "${TMP}/port" ]] && break; sleep 0.1; done
STUB="http://127.0.0.1:$(cat "${TMP}/port")"
MODEL="${STUB}/v1"

# ── `decree`: emit is a file per message; check exits with $TMP/check-rc ──────
mkdir -p "${TMP}/bin" "${TMP}/emits"
cat > "${TMP}/bin/decree" <<'SH'
#!/usr/bin/env bash
case "$1" in
  check) exit "$(cat "${STUBDIR}/check-rc" 2>/dev/null || echo 0)" ;;
  emit)  n=$(( $(find "${STUBDIR}/emits" -name '*.args' | wc -l) + 1 ))
         printf '%s\n' "$*" > "${STUBDIR}/emits/${n}.args"; cat > "${STUBDIR}/emits/${n}" ;;
esac
SH
chmod +x "${TMP}/bin/decree"
emits() { cat "${TMP}"/emits/*.args 2>/dev/null; }
reset_emits() { rm -f "${TMP}"/emits/*; }

# ── The workspace, which is also the decree project root ─────────────────────
W="${TMP}/ws"
mkdir -p "$W/.decree/machines" "$W/.decree/scripts" "$W/.decree/migrations" "$W/notes/ideas"
cp "${REPO_DIR}/automation/machines/note_watch.yml" "$W/.decree/machines/"
printf 'name: notify\n' > "$W/.decree/machines/notify.yml"

run() {  # run <script> [VAR=value...]: one decree run of a shipped script, in the workspace
    local script="$1"; shift
    mkdir -p "${TMP}/run" "${TMP}/store"
    ( cd "$W" && env PATH="${TMP}/bin:${PATH}" STUBDIR="$TMP" DECREE_LIB="${REPO_DIR}/automation/lib" \
        DECREE_STORE="${TMP}/store" DECREE_RUN_DIR="${TMP}/run" AUTOMATIONS_WORKSPACE="$W" \
        EXIST_MODEL_URL="${MODEL_URL_UNDER_TEST:-$MODEL}" EXIST_MODEL_CHAT=test-model FIRECRAWL_URL="$STUB" "$@" \
        bash "$script" ) > "${TMP}/last.log" 2>&1
    echo $?
}
SCRIPTS="${REPO_DIR}/automation/scripts"
NAME=business_idea_workup

echo ""; echo "=== watch ==="
printf '# How I work ideas\n\nNext time I have a business idea, research who already does it and draft a one-page plan.\n' > "$W/notes/process.md"
jq -n '{instruction: {name: "Business idea workup", when: "I write down a new business idea", steps: ["research who already does it", "draft a one-page plan"]}, matches: []}' > "${TMP}/watch-reply"
assert_eq "note_watch reads the note" "0" "$(run "$SCRIPTS/note_watch.sh" DECREE_DATA_PATH=notes/process.md)"
assert_has "a standing instruction becomes an automation_propose run" "$(emits)" "--machine automation_propose --param note_path=notes/process.md --param name=${NAME}"
assert_has "...with the event" "$(emits)" "--param when=I write down a new business idea"
reset_emits
assert_eq "the same note again" "0" "$(run "$SCRIPTS/note_watch.sh" DECREE_DATA_PATH=notes/process.md)"
assert_eq "...is not proposed twice" "" "$(emits)"
MODEL_URL_UNDER_TEST="http://127.0.0.1:9/v1"
assert_eq "with no model, note_watch still succeeds" "0" "$(run "$SCRIPTS/note_watch.sh" DECREE_DATA_PATH=notes/process.md)"
unset MODEL_URL_UNDER_TEST
assert_eq "...and starts nothing" "" "$(emits)"
assert_eq "its own automations folder is never read as a note" "0" "$(run "$SCRIPTS/note_watch.sh" DECREE_DATA_PATH=notes/automations/x.md)"
assert_has "...it says so" "$(cat "${TMP}/last.log")" "is not watched"

echo ""; echo "=== propose ==="
cat > "${TMP}/spec-reply" <<'MD'
# A new business idea gets researched and planned

## Overview
"Next time I have a business idea, research who already does it and draft a one-page plan."

## Outcome
- What starts it: a note of theirs that is a new business idea.
- Who already does it, and a one-page plan.

## Constraints
- Writes nothing outside ai/automations/business_idea_workup/.

## Acceptance Criteria
- **Given** a new idea note **When** it settles **Then** a plan is in ai/automations/business_idea_workup/
MD
PROPOSAL="$W/notes/automations/proposed/${NAME}.md"
propose() { run "$SCRIPTS/automation_propose.sh" DECREE_DATA_NOTE_PATH=notes/process.md DECREE_DATA_NAME="$1" \
    "DECREE_DATA_WHEN=I write down a new business idea" "DECREE_DATA_STEPS=- research who already does it
- draft a one-page plan"; }
assert_eq "automation_propose runs" "0" "$(propose $NAME)"
assert_has "the proposal is a migration for develop" "$(head -5 "$PROPOSAL" 2>/dev/null)" "machine: develop"
assert_has "...naming its automation" "$(head -5 "$PROPOSAL" 2>/dev/null)" "automation: ${NAME}"
assert_has "...and the note that asked" "$(head -5 "$PROPOSAL" 2>/dev/null)" "from: notes/process.md"
assert_has "...with the intent and the outcome" "$(cat "$PROPOSAL" 2>/dev/null)" "## Outcome"
assert_has "you are told how to accept it" "$(cat "${TMP}"/emits/* 2>/dev/null)" "move notes/automations/proposed/${NAME}.md up to notes/automations/"
reset_emits
printf '# Something\n\n## Overview\nx\n' > "${TMP}/spec-reply"
assert_eq "a migration missing a section fails the run" "1" "$(propose other_thing)"
assert_eq "...and writes no proposal" "no" "$([[ -e "$W/notes/automations/proposed/other_thing.md" ]] && echo yes || echo no)"

echo ""; echo "=== accept ==="
reset_emits
mv "$PROPOSAL" "$W/notes/automations/${NAME}.md"
assert_eq "accepting it reconciles" "0" "$(run "$SCRIPTS/reconcile.sh" DECREE_DATA_PATH="notes/automations/${NAME}.md" DECREE_DATA_CHANGE=created)"
MIGRATION="$(cd "$W/.decree/migrations" && ls A*-"${NAME}".md 2>/dev/null)"
assert_has "it is filed as a pending migration" "$MIGRATION" "-${NAME}.md"
assert_eq "...holding the spec as written" "same" "$(cmp -s "$W/notes/automations/${NAME}.md" "$W/.decree/migrations/${MIGRATION}" && echo same)"
assert_has "you are told it is being built" "$(emits)" "ntfy_title=Building an automation"
printf -- '---\nmachine: develop\nautomation: notify\nfrom: notes/x.md\n---\n# x\n' > "$W/notes/automations/notify.md"
assert_eq "a name decree already has is refused" "1" "$(run "$SCRIPTS/reconcile.sh" DECREE_DATA_PATH=notes/automations/notify.md DECREE_DATA_CHANGE=created)"
assert_eq "...and that machine is untouched" "name: notify" "$(cat "$W/.decree/machines/notify.yml")"
rm -f "$W/notes/automations/notify.md"

echo ""; echo "=== web ==="
web() { ( export FIRECRAWL_URL="$1"; source "${REPO_DIR}/automation/lib/firecrawl.sh"; shift; "$@" ) 2>&1; }
SOURCES="$(web "$STUB" web_search "dog walking subscriptions")"
assert_has "web_search gives each result as a source with its URL" "$SOURCES" '<source url="https://walkies.example/plans">'
assert_has "...its title" "$SOURCES" "# Walkies: dog walking plans"
assert_has "...and the page's text" "$SOURCES" "Monthly plans from \$99, for: dog walking subscriptions"
assert_has "web_read gives one page" "$(web "$STUB" web_read https://walkies.example/)" "# Page at https://walkies.example/"
assert_has "with Firecrawl off, web_search says how to turn it on" "$(web "" web_search x)" "EXIST_IS_AI_FIRECRAWL=true"
assert_has "...and an unreachable one says so" "$(web "http://127.0.0.1:9" web_search x)" "no answer from"
assert_eq "...and fails" "1" "$(web "http://127.0.0.1:9" web_search x >/dev/null; echo $?)"

echo ""; echo "=== develop ==="
reset_emits
develop() { run "$SCRIPTS/develop.sh" DECREE_MESSAGE="$W/.decree/migrations/${MIGRATION}" DECREE_DATA_AUTOMATION="$1" DECREE_DATA_FROM=notes/process.md; }
cat > "${TMP}/build-reply" <<'BUILD'
TRIGGER: {"kind": "note", "when": "a new business idea"}
steps() {
    local sources
    sources="$(web_search "competitors: $(head -1 <<<"$NOTE")" 5)"
    echo "## Verdict"
    ask "Favorable, unfavorable, or already done. Use only the sources below; cite URLs." "$NOTE

$sources"
    echo "## Existing solutions"
    printf '%s\n' "$sources" | sed -n 's/^<source url="\(.*\)">$/- \1/p'
    echo "## One-page plan"
    ask "Draft a one-page plan." "$NOTE"
}
BUILD
assert_eq "develop builds it" "0" "$(develop $NAME)"
assert_has "with Firecrawl on, the model is told to put a verdict first" "$(cat "${TMP}/build-system" 2>/dev/null)" '"## Verdict"'
assert_has "...through web_search" "$(cat "${TMP}/build-system" 2>/dev/null)" 'web_search "<query>"'
assert_has "its machine invokes its script" "$(cat "$W/.decree/machines/${NAME}.yml" 2>/dev/null)" "invoke: ${NAME}"
assert_eq "its script is executable" "yes" "$([[ -x "$W/.decree/scripts/${NAME}.sh" ]] && echo yes || echo no)"
assert_has "...and runs the built steps inside the shared frame" "$(cat "$W/.decree/scripts/${NAME}.sh" 2>/dev/null)" 'source "${DECREE_LIB}/automations/run.sh"'
assert_eq "its note trigger is in the registry" "a new business idea" "$(yq -r ".[] | select(.machine == \"${NAME}\") | .when" "$W/.decree/automations.yml")"
assert_has "note_watch may start it" "$(yq -r '.states.watch.emits | join(" ")' "$W/.decree/machines/note_watch.yml")" "$NAME"
assert_eq "what it was built from is recorded" "same" "$(cmp -s "$W/.decree/migrations/${MIGRATION}" "$W/.decree/applied/${MIGRATION}" && echo same)"
assert_has "you are told it is built" "$(emits)" "ntfy_title=Automation built"

# A file trigger and a cron trigger, each on a scratch name.
cp "$W/.decree/migrations/${MIGRATION}" "$W/.decree/migrations/A1-pdf_filer.md"
printf 'TRIGGER: {"kind": "file", "match": "inbox/*.pdf", "changes": ["created"], "quiet": 10}\nsteps() { echo "## Filed"; }\n' > "${TMP}/build-reply"
assert_eq "a file trigger builds" "0" "$(run "$SCRIPTS/develop.sh" DECREE_MESSAGE="$W/.decree/migrations/A1-pdf_filer.md" DECREE_DATA_AUTOMATION=pdf_filer)"
assert_eq "...as a file handler" "inbox/*.pdf" "$(yq -r '.[] | select(.machine == "pdf_filer") | .match' "$W/.decree/handlers.yml")"
printf 'TRIGGER: {"kind": "cron", "cron": "0 8 * * MON"}\nsteps() { echo "## Weekly"; }\n' > "${TMP}/build-reply"
cp "$W/.decree/migrations/${MIGRATION}" "$W/.decree/migrations/A2-weekly_thing.md"
assert_eq "a cron trigger builds" "0" "$(run "$SCRIPTS/develop.sh" DECREE_MESSAGE="$W/.decree/migrations/A2-weekly_thing.md" DECREE_DATA_AUTOMATION=weekly_thing)"
assert_has "...as a cron file" "$(cat "$W/.decree/cron/weekly_thing.md" 2>/dev/null)" 'cron: "0 8 * * MON"'
# A trigger that would run on its own output fails the gate, changes nothing, and is shown next time.
printf 'TRIGGER: {"kind": "file", "match": "ai/automations/*.md"}\nsteps() { echo "## x"; }\n' > "${TMP}/build-reply"
cp "$W/.decree/migrations/${MIGRATION}" "$W/.decree/migrations/A3-loop_thing.md"
assert_eq "a trigger on its own output fails the gate" "1" "$(run "$SCRIPTS/develop.sh" DECREE_MESSAGE="$W/.decree/migrations/A3-loop_thing.md" DECREE_DATA_AUTOMATION=loop_thing)"
assert_eq "...and nothing is installed" "no" "$([[ -e "$W/.decree/machines/loop_thing.yml" ]] && echo yes || echo no)"
run "$SCRIPTS/develop.sh" DECREE_MESSAGE="$W/.decree/migrations/A3-loop_thing.md" DECREE_DATA_AUTOMATION=loop_thing >/dev/null
assert_has "the next attempt is shown what failed" "$(cat "${TMP}/build-prompt")" "would match its own output"
printf 'TRIGGER: {"kind": "note", "when": "x"}\nsteps() { echo "## x"; }\n' > "${TMP}/build-reply"
echo 1 > "${TMP}/check-rc"
assert_eq "a build that fails decree check fails" "1" "$(run "$SCRIPTS/develop.sh" DECREE_MESSAGE="$W/.decree/migrations/A3-loop_thing.md" DECREE_DATA_AUTOMATION=loop_thing)"
echo 0 > "${TMP}/check-rc"
assert_eq "...and is undone" "no" "$([[ -e "$W/.decree/machines/loop_thing.yml" || -e "$W/.decree/scripts/loop_thing.sh" ]] && echo yes || echo no)"
assert_lacks "...registry entry included" "$(cat "$W/.decree/automations.yml")" "loop_thing"
assert_has "...the others are still there" "$(cat "$W/.decree/automations.yml")" "pdf_filer"

# With Firecrawl off, the model is not told about the web, and steps that use it fail the gate.
cp "$W/.decree/migrations/${MIGRATION}" "$W/.decree/migrations/A4-offline_thing.md"
printf 'TRIGGER: {"kind": "note", "when": "x"}\nsteps() { web_search "x"; }\n' > "${TMP}/build-reply"
assert_eq "with Firecrawl off, steps that search the web fail the gate" "1" "$(run "$SCRIPTS/develop.sh" DECREE_MESSAGE="$W/.decree/migrations/A4-offline_thing.md" DECREE_DATA_AUTOMATION=offline_thing FIRECRAWL_URL=)"
assert_has "...saying why" "$(cat "${TMP}/last.log")" "need Firecrawl, which is off"
assert_lacks "...and the model was not offered web_search" "$(cat "${TMP}/build-system")" "web_search"
assert_eq "...and nothing is installed" "no" "$([[ -e "$W/.decree/machines/offline_thing.yml" || -e "$W/.decree/scripts/offline_thing.sh" ]] && echo yes || echo no)"
rm -f "${TMP}/run/gate.err"

echo ""; echo "=== trigger ==="
reset_emits
printf '# Dog walking subscriptions\n\nA monthly plan for busy owners in my neighbourhood.\n' > "$W/notes/ideas/dog-walking.md"
jq -n --arg n "$NAME" '{instruction: null, matches: [$n, "notify", "pdf_filer"]}' > "${TMP}/watch-reply"
assert_eq "a later note is read" "0" "$(run "$SCRIPTS/note_watch.sh" DECREE_DATA_PATH=notes/ideas/dog-walking.md)"
assert_has "the automation whose event it is starts on it" "$(emits)" "--machine ${NAME} --param note_path=notes/ideas/dog-walking.md"
assert_lacks "a matched name that was never accepted starts nothing" "$(emits)" "--machine notify"
assert_lacks "...nor one whose trigger is not a note" "$(emits)" "--machine pdf_filer"
reset_emits
assert_eq "the automation runs" "0" "$(run "$W/.decree/scripts/${NAME}.sh" DECREE_DATA_NOTE_PATH=notes/ideas/dog-walking.md)"
RESULT="$(cat "$W/ai/automations/${NAME}/"*-dog-walking.md 2>/dev/null)"
assert_has "its results are written to ai/automations/<name>/" "$RESULT" "## One-page plan"
assert_has "...with what the model answered for each step" "$RESULT" "ANSWER to Draft a one-page pla"
assert_has "it searched the web for the idea" "$(cat "${TMP}/searches" 2>/dev/null)" "competitors: # Dog walking subscriptions"
assert_has "...and the verdict is drawn from those pages" "$RESULT" "ANSWER to Favorable, unfavorab about # Dog walking subscriptions, citing walkies.example"
assert_has "...which it lists as existing solutions" "$RESULT" "https://walkies.example/plans"
assert_has "the verdict is what reaches your phone" "$(head -3 "${TMP}/emits/1" 2>/dev/null)" "## Verdict"
assert_has "...linked to the note it ran for" "$RESULT" "[notes/ideas/dog-walking.md](../../../notes/ideas/dog-walking.md)"
assert_has "...and you are told where" "$(cat "${TMP}"/emits/* 2>/dev/null)" "All of it: ai/automations/${NAME}/"

echo ""; echo "=== edit ==="
reset_emits
echo "$MIGRATION" > "$W/.decree/processed.md"
printf '\n- Also: a name for it.\n' >> "$W/notes/automations/${NAME}.md"
assert_eq "an edited spec reconciles" "0" "$(run "$SCRIPTS/reconcile.sh" DECREE_DATA_PATH="notes/automations/${NAME}.md" DECREE_DATA_CHANGE=modified)"
assert_has "...and, already built, its migration runs again" "$(cat "${TMP}"/emits/* 2>/dev/null)" "Also: a name for it."
assert_has "...you are told" "$(emits)" "ntfy_title=Rebuilding an automation"
cp "$W/.decree/migrations/${MIGRATION}" "$W/.decree/applied/${MIGRATION}"
reset_emits
assert_eq "an unchanged spec" "0" "$(run "$SCRIPTS/reconcile.sh" DECREE_DATA_PATH="notes/automations/${NAME}.md" DECREE_DATA_CHANGE=modified)"
assert_eq "...runs nothing" "" "$(emits)"

echo ""; echo "=== remove ==="
reset_emits
rm "$W/notes/automations/${NAME}.md"
assert_eq "deleting the spec removes it" "0" "$(run "$SCRIPTS/reconcile.sh" DECREE_DATA_PATH="notes/automations/${NAME}.md" DECREE_DATA_CHANGE=deleted)"
assert_eq "...machine, script and migration are gone" "no" "$([[ -e "$W/.decree/machines/${NAME}.yml" || -e "$W/.decree/scripts/${NAME}.sh" || -e "$W/.decree/migrations/${MIGRATION}" ]] && echo yes || echo no)"
assert_lacks "...so is its registry entry" "$(cat "$W/.decree/automations.yml")" "$NAME"
assert_lacks "...and note_watch can no longer start it" "$(yq -r '.states.watch.emits | join(" ")' "$W/.decree/machines/note_watch.yml")" "$NAME"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→exit path is proven (run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
