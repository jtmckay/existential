#!/usr/bin/env bash
# test-automations.sh — a note asks for an automation; it is proposed as a spec,
# built by develop as a plugin file and OFFERED, and only the host installs it.
# note_watch, automation_propose, reconcile, develop and lib/automations/run.sh, with
# the model and, while their scripts run, `decree` stubbed:
#
#   watch     a standing instruction becomes one automation_propose, once; with no
#             model reachable nothing happens and the run still succeeds
#   propose   the proposal is a spec for develop: intent, outcome, constraints,
#             acceptance criteria; an answer missing a section fails the run
#   build     moving the spec into notes/automations/ hands it to develop; a
#             plugin file moved there installs nothing
#   web       web_search and web_read return Firecrawl's pages as Markdown
#   develop   builds ONE PLUGIN FILE in ai/proposed/ (machine, script, and its
#             trigger as when:, handlers: or cron:), installs nothing, and tells
#             you where to read it and how to install it; a
#             failed gate offers nothing and keeps its errors for the next attempt
#   claude    signed in, develop builds with Claude and may use agent
#   accepted  the offer, moved into .decree/plugins/ and installed (decree
#             installs it, the sync wires its trigger): script, note_watch, handler, cron;
#             and decree exports it with its trigger
#   trigger   a later note the model matches starts it, and only an installed one
#   edit      a changed spec is offered again; remove: deleting it removes nothing
#   share     an installed plugin is sent as its file; one another stack offers
#             waits in ai/proposed/; lists and requests between stacks
#   sync      the repo's plugins dir: a project's plugins/ is what is on and what
#             that needs, and decree installs it; a changed file is installed
#             again, an edited copy archived by decree first; auto_update off only
#             names it; one no longer wanted goes, cron and lib too; a flow brings
#             its order files; decree 0.5's copies are converted
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
    if (req.url.startsWith("/cb/")) { fs.writeFileSync(`${dir}/posted`, `${req.url}\n${req.headers.authorization || ""}\n${body}`); return res.end("{}"); }
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
# The plugins under test, installed with the real decree as the stack installs
# them (lib/plugin.sh); their scripts then run there with the stub
# decree first on PATH.
command -v decree >/dev/null || { echo "automations: needs decree (run it through ./existential.sh test unit)"; exit 1; }
W="${TMP}/ws"
mkdir -p "$W/notes/ideas" "$W/notes/automations"
( source "${REPO_DIR}/automation/lib/plugin.sh"
  plugin_unpack notify note_watch automation_propose reconcile develop plugin_share plugin_offer plugin_request "$W" ) >/dev/null

run() {  # run <script> [VAR=value...]: one decree run of a shipped script, in the workspace
    local script="$1"; shift
    mkdir -p "${TMP}/run" "${TMP}/store"
    ( cd "$W" && env PATH="${TMP}/bin:${PATH}" STUBDIR="$TMP" \
        DECREE_STATE_DIR="${TMP}/store" DECREE_RUN_DIR="${TMP}/run" AUTOMATIONS_WORKSPACE="$W" \
        HOME="${TMP}/home" DECREE_STATE=run ANTHROPIC_API_KEY= CLAUDE_CODE_OAUTH_TOKEN= \
        EXIST_MODEL_URL="${MODEL_URL_UNDER_TEST:-$MODEL}" EXIST_MODEL_CHAT=test-model FIRECRAWL_URL="$STUB" "$@" \
        bash "$script" ) > "${TMP}/last.log" 2>&1
    echo $?
}
plugin_script() { echo "$W/.decree/machines/$1/scripts/$1.sh"; }
NAME=business_idea_workup

echo ""; echo "=== watch ==="
printf '# How I work ideas\n\nNext time I have a business idea, research who already does it and draft a one-page plan.\n' > "$W/notes/process.md"
jq -n '{instruction: {name: "Business idea workup", when: "I write down a new business idea", steps: ["research who already does it", "draft a one-page plan"]}, matches: []}' > "${TMP}/watch-reply"
assert_eq "note_watch reads the note" "0" "$(run "$(plugin_script note_watch)" DECREE_DATA_PATH=notes/process.md)"
assert_has "a standing instruction becomes an automation_propose run" "$(emits)" "--machine automation_propose --param note_path=notes/process.md --param name=${NAME}"
assert_has "...with the event" "$(emits)" "--param when=I write down a new business idea"
reset_emits
assert_eq "the same note again" "0" "$(run "$(plugin_script note_watch)" DECREE_DATA_PATH=notes/process.md)"
assert_eq "...is not proposed twice" "" "$(emits)"
MODEL_URL_UNDER_TEST="http://127.0.0.1:9/v1"
assert_eq "with no model, note_watch still succeeds" "0" "$(run "$(plugin_script note_watch)" DECREE_DATA_PATH=notes/process.md)"
unset MODEL_URL_UNDER_TEST
assert_eq "...and starts nothing" "" "$(emits)"
assert_eq "its own automations folder is never read as a note" "0" "$(run "$(plugin_script note_watch)" DECREE_DATA_PATH=notes/automations/x.md)"
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
PROPOSAL="$W/ai/proposed/${NAME}.md"
propose() { run "$(plugin_script automation_propose)" DECREE_DATA_NOTE_PATH=notes/process.md DECREE_DATA_NAME="$1" \
    "DECREE_DATA_WHEN=I write down a new business idea" "DECREE_DATA_STEPS=- research who already does it
- draft a one-page plan"; }
assert_eq "automation_propose runs" "0" "$(propose $NAME)"
assert_has "the proposal is a migration for develop" "$(head -5 "$PROPOSAL" 2>/dev/null)" "machine: develop"
assert_has "...naming its automation" "$(head -5 "$PROPOSAL" 2>/dev/null)" "automation: ${NAME}"
assert_has "...and the note that asked" "$(head -5 "$PROPOSAL" 2>/dev/null)" "from: notes/process.md"
assert_has "...with the intent and the outcome" "$(cat "$PROPOSAL" 2>/dev/null)" "## Outcome"
assert_has "you are told how to accept it" "$(cat "${TMP}"/emits/* 2>/dev/null)" "move ai/proposed/${NAME}.md into notes/automations/"
reset_emits
printf '# Something\n\n## Overview\nx\n' > "${TMP}/spec-reply"
assert_eq "a migration missing a section fails the run" "1" "$(propose other_thing)"
assert_eq "...and writes no proposal" "no" "$([[ -e "$W/ai/proposed/other_thing.md" ]] && echo yes || echo no)"

echo ""; echo "=== build ==="
reset_emits
mv "$PROPOSAL" "$W/notes/automations/${NAME}.md"
assert_eq "moving the spec into notes/automations/ reconciles" "0" "$(run "$(plugin_script reconcile)" DECREE_DATA_PATH="notes/automations/${NAME}.md" DECREE_DATA_CHANGE=created)"
assert_has "...which hands it to develop" "$(emits)" "--machine develop --param automation=${NAME}"
assert_has "...with the spec as written" "$(cat "${TMP}"/emits/* 2>/dev/null)" "## Acceptance Criteria"
assert_has "you are told it is being built, and that nothing runs yet" "$(cat "${TMP}"/emits/* 2>/dev/null)" "Nothing runs until you install it."
assert_eq "...and nothing is filed or installed" "no" "$([[ -e "$W/.decree/migrations" && -n "$(ls "$W/.decree/migrations" 2>/dev/null)" ]] && echo yes || echo no)"
reset_emits
cp "${REPO_DIR}/automation/plugins/gpu_lease.md" "$W/notes/automations/gpu_lease.md"
assert_eq "a plugin file moved there reconciles" "0" "$(run "$(plugin_script reconcile)" DECREE_DATA_PATH=notes/automations/gpu_lease.md DECREE_DATA_CHANGE=created)"
assert_has "...and installs nothing: you are told how" "$(cat "${TMP}"/emits/* 2>/dev/null)" "Move it into .decree/plugins/ and run: decree install gpu_lease"
assert_lacks "...and develop is not asked" "$(emits)" "--machine develop"
rm -f "$W/notes/automations/gpu_lease.md"

echo ""; echo "=== web ==="
web() { ( export FIRECRAWL_URL="$1"; source "${W}/.decree/lib/firecrawl.sh"; shift; "$@" ) 2>&1; }
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
SPEC="$W/notes/automations/${NAME}.md"
develop() { run "$(plugin_script develop)" DECREE_MESSAGE="$SPEC" DECREE_DATA_AUTOMATION="$1" DECREE_DATA_FROM=notes/process.md "${@:2}"; }
offer() { echo "$W/ai/proposed/$1.md"; }
in_offer() { yq --front-matter=extract -r "$2" "$(offer "$1")" 2>/dev/null; }
before="$(cd "$W/.decree" && find machines plugins -type f | sort | xargs cksum)"
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
assert_eq "develop builds it" "0" "$(develop $NAME EXIST_TAILNET_NAME=box.ts.net)"
assert_has "with Firecrawl on, the model is told to put a verdict first" "$(cat "${TMP}/build-system" 2>/dev/null)" '"## Verdict"'
assert_has "...through web_search" "$(cat "${TMP}/build-system" 2>/dev/null)" 'web_search "<query>"'
assert_eq "what it built is one plugin file, offered in ai/proposed/" "${NAME} automation" "$(in_offer $NAME '[.name, .["x-exist-project"]] | join(" ")')"
assert_eq "...whose machine invokes its script" "$NAME" "$(in_offer $NAME '.machine.states.run.invoke')"
assert_has "...which runs the built steps inside the shared frame" "$(in_offer $NAME ".scripts[\"${NAME}.sh\"]")" 'source ".decree/lib/automations/run.sh"'
assert_eq "...whose note trigger is its x-exist-when" "a new business idea" "$(in_offer $NAME '.["x-exist-when"]')"
assert_eq "...and which needs develop, whose frame it runs in" "develop" "$(in_offer $NAME '.needs | join(" ")')"
assert_eq "NOTHING is installed: machines/ and plugins/ are as they were" "$before" "$(cd "$W/.decree" && find machines plugins -type f | sort | xargs cksum)"
assert_has "you are told it is ready to review" "$(emits)" "ntfy_title=Automation ready to review"
assert_has "...and how to install it" "$(cat "${TMP}"/emits/* 2>/dev/null)" "mv ai/proposed/${NAME}.md .decree/plugins/ && decree install ${NAME}"

# A file trigger and a cron trigger, each on a scratch name.
printf 'TRIGGER: {"kind": "file", "match": "inbox/*.pdf", "changes": ["created"], "quiet": 10}\nsteps() { echo "## Filed"; }\n' > "${TMP}/build-reply"
assert_eq "a file trigger builds" "0" "$(develop pdf_filer)"
assert_eq "...as an x-exist-handlers entry" "inbox/*.pdf 10" "$(in_offer pdf_filer '.["x-exist-handlers"][0] | [.match, .quiet] | join(" ")')"
printf 'TRIGGER: {"kind": "cron", "cron": "0 8 * * MON"}\nsteps() { echo "## Weekly"; }\n' > "${TMP}/build-reply"
assert_eq "a cron trigger builds" "0" "$(develop weekly_thing)"
assert_has "...as a cron file" "$(in_offer weekly_thing '.cron["weekly_thing.md"]')" 'cron: "0 8 * * MON"'
# A trigger that would run on its own output fails the gate, offers nothing, and is shown next time.
printf 'TRIGGER: {"kind": "file", "match": "ai/automations/*.md"}\nsteps() { echo "## x"; }\n' > "${TMP}/build-reply"
assert_eq "a trigger on its own output fails the gate" "1" "$(develop loop_thing)"
assert_eq "...and nothing is offered" "no" "$([[ -e "$(offer loop_thing)" ]] && echo yes || echo no)"
develop loop_thing >/dev/null
assert_has "the next attempt is shown what failed" "$(cat "${TMP}/build-prompt")" "would match its own output"
printf 'TRIGGER: {"kind": "note", "when": "x"}\nsteps() { echo "## x"; }\n' > "${TMP}/build-reply"
echo 1 > "${TMP}/check-rc"
assert_eq "a build that fails decree check fails" "1" "$(develop loop_thing)"
echo 0 > "${TMP}/check-rc"
assert_eq "...and is not offered" "no" "$([[ -e "$(offer loop_thing)" ]] && echo yes || echo no)"
assert_eq "a name the stack ships is never offered" "1" "$(develop notify)"
assert_has "...saying why" "$(cat "${TMP}/last.log")" "refusing to offer one by its name"

# With Firecrawl off, the model is not told about the web, and steps that use it fail the gate.
printf 'TRIGGER: {"kind": "note", "when": "x"}\nsteps() { web_search "x"; }\n' > "${TMP}/build-reply"
assert_eq "with Firecrawl off, steps that search the web fail the gate" "1" "$(develop offline_thing FIRECRAWL_URL=)"
assert_has "...saying why" "$(cat "${TMP}/last.log")" "need Firecrawl, which is off"
assert_lacks "...and the model was not offered web_search" "$(cat "${TMP}/build-system")" "web_search"
assert_eq "...and nothing is offered" "no" "$([[ -e "$(offer offline_thing)" ]] && echo yes || echo no)"
rm -f "${TMP}/run/gate.err"

echo ""; echo "=== claude ==="
# A stub claude: records what it was asked, answers with build-reply.
cat > "${TMP}/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${@: -1}" > "${STUBDIR}/claude-prompt"
cat "${STUBDIR}/build-reply"
SH
chmod +x "${TMP}/bin/claude"
SIGNED_IN=CLAUDE_CODE_OAUTH_TOKEN=test-token
printf 'TRIGGER: {"kind": "note", "when": "x"}\nsteps() {\n    echo "## Found"\n    agent "find my notes about x"\n}\nThat is the function.\n' > "${TMP}/build-reply"
rm -f "${TMP}/build-system"
assert_eq "signed in to Claude, develop builds with it" "0" "$(develop file_reader "$SIGNED_IN")"
assert_has "...asking it to build the automation" "$(cat "${TMP}/claude-prompt" 2>/dev/null)" "You build one automation"
assert_has "...with the spec" "$(cat "${TMP}/claude-prompt" 2>/dev/null)" "The spec:"
assert_has "...and telling it about agent" "$(cat "${TMP}/claude-prompt" 2>/dev/null)" 'agent "<task>"'
assert_eq "...and the chat model is not asked" "no" "$([[ -e "${TMP}/build-system" ]] && echo yes || echo no)"
assert_has "the built steps can call agent" "$(in_offer file_reader '.scripts["file_reader.sh"]')" 'agent "find my notes about x"'
assert_lacks "...and words after the function are no part of it" "$(in_offer file_reader '.scripts["file_reader.sh"]')" "That is the function"
printf 'source ".decree/lib/agent.sh"\nagent "hello"\n' > "${TMP}/agent-call.sh"
assert_eq "agent answers when signed in" "0" "$(run "${TMP}/agent-call.sh" "$SIGNED_IN")"
assert_has "...with Claude's reply" "$(cat "${TMP}/last.log")" "That is the function"
assert_has "...and the call is logged" "$(cat "$W/.decree/ai-use.md" 2>/dev/null)" "| claude |"
assert_eq "agent fails when not signed in" "1" "$(run "${TMP}/agent-call.sh")"
assert_has "...saying how to sign in" "$(cat "${TMP}/last.log")" "in code-server's terminal: claude, then /login"
printf 'TRIGGER: {"kind": "note", "when": "x"}\nsteps() { agent "x"; }\n' > "${TMP}/build-reply"
assert_eq "not signed in, steps that call agent fail the gate" "1" "$(develop unsigned_thing)"
assert_has "...saying why" "$(cat "${TMP}/last.log")" "agent needs Claude signed in"
assert_lacks "...and the chat model was not offered agent" "$(cat "${TMP}/build-system")" 'agent "<task>"'
rm -f "${TMP}/run/gate.err"

echo ""; echo "=== accepted ==="
# Installed in the workspace: the offer moved into .decree/plugins/ and `decree
# install`ed; the sync (the host's next ./existential.sh) wires its trigger.
printf 'on: [note_watch, automation_propose, reconcile, develop, plugin_share, plugin_offer, plugin_request]\n' > "${TMP}/plugins.yml"
host_install() {  # <name>: mv + decree install, then the sync (run in $(), so the list is a file)
    mv "$(offer "$1")" "$W/.decree/plugins/$1.md"
    ( cd "$W" && decree install --no-color "$1" && PLUGINS_ON="${TMP}/plugins.yml" bash -c 'source "$1"; plugin_sync "$2" automation' _ \
        "${REPO_DIR}/automation/lib/plugin.sh" "${REPO_DIR}/automation/plugins" ) > "${TMP}/last.log" 2>&1; echo $?
}
assert_eq "the offer installs" "0" "$(host_install $NAME)"
assert_eq "...its script in machines/<name>/scripts/, executable" "yes" "$([[ -x "$W/.decree/machines/${NAME}/scripts/${NAME}.sh" ]] && echo yes || echo no)"
assert_eq "...from its plugin file, which keeps its note trigger" "a new business idea" "$(yq --front-matter=extract -r '.["x-exist-when"]' "$W/.decree/plugins/${NAME}.md")"
assert_has "...and note_watch may start it" "$(yq -r '.states.watch.emits | join(" ")' "$W/.decree/machines/note_watch/machine.yml")" "$NAME"
assert_eq "a file trigger installs" "0" "$(host_install pdf_filer)"
assert_eq "...as a file handler for its machine" "inbox/*.pdf" "$(yq -r '.[] | select(.machine == "pdf_filer") | .match' "$W/.decree/handlers.yml")"
assert_eq "a cron trigger installs" "0" "$(host_install weekly_thing)"
assert_has "...as a cron file" "$(cat "$W/.decree/machines/weekly_thing/cron/weekly_thing.md" 2>/dev/null)" 'cron: "0 8 * * MON"'
( cd "$W" && decree export --no-color pdf_filer ) >/dev/null 2>&1
assert_eq "an installed one exports with its trigger" "inbox/*.pdf" "$(yq --front-matter=extract -r '.["x-exist-handlers"][0].match' "$W/.decree/plugins/pdf_filer.md")"

echo ""; echo "=== trigger ==="
reset_emits
printf '# Dog walking subscriptions\n\nA monthly plan for busy owners in my neighbourhood.\n' > "$W/notes/ideas/dog-walking.md"
jq -n --arg n "$NAME" '{instruction: null, matches: [$n, "notify", "pdf_filer"]}' > "${TMP}/watch-reply"
assert_eq "a later note is read" "0" "$(run "$(plugin_script note_watch)" DECREE_DATA_PATH=notes/ideas/dog-walking.md)"
assert_has "the automation whose event it is starts on it" "$(emits)" "--machine ${NAME} --param note_path=notes/ideas/dog-walking.md"
assert_lacks "a matched name that was never accepted starts nothing" "$(emits)" "--machine notify"
assert_lacks "...nor one whose trigger is not a note" "$(emits)" "--machine pdf_filer"
reset_emits
assert_eq "the automation runs" "0" "$(run "$W/.decree/machines/${NAME}/scripts/${NAME}.sh" DECREE_DATA_NOTE_PATH=notes/ideas/dog-walking.md)"
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
printf 'TRIGGER: {"kind": "note", "when": "x"}\nsteps() { echo "## x"; }\n' > "${TMP}/build-reply"
printf '\n- Also: a name for it.\n' >> "$SPEC"
assert_eq "an edited spec reconciles" "0" "$(run "$(plugin_script reconcile)" DECREE_DATA_PATH="notes/automations/${NAME}.md" DECREE_DATA_CHANGE=modified)"
assert_has "...and develop is asked for a new offer" "$(cat "${TMP}"/emits/* 2>/dev/null)" "Also: a name for it."
assert_eq "an already accepted one may be offered again" "0" "$(develop $NAME)"
assert_eq "...as a new file to review" "yes" "$([[ -e "$(offer $NAME)" ]] && echo yes || echo no)"

echo ""; echo "=== remove ==="
reset_emits
rm "$SPEC"
assert_eq "deleting the spec reconciles" "0" "$(run "$(plugin_script reconcile)" DECREE_DATA_PATH="notes/automations/${NAME}.md" DECREE_DATA_CHANGE=deleted)"
assert_eq "...and removes nothing" "yes" "$([[ -e "$W/.decree/machines/${NAME}/machine.yml" ]] && echo yes || echo no)"
assert_has "...you are told how to turn it off" "$(cat "${TMP}"/emits/* 2>/dev/null)" "rm .decree/plugins/${NAME}.md && decree install"


echo ""; echo "=== share ==="
# Plugins move between stacks as files: an installed one is sent as the file it
# was installed from, and one offered by another stack waits in ai/proposed/ like any offer.
reset_emits
PLUGIN=gpu_lease
( source "${REPO_DIR}/automation/lib/plugin.sh"; plugin_unpack "$PLUGIN" "$W" ) >/dev/null
script_of() { echo "$W/.decree/machines/$1/scripts/$2.sh"; }
rm -f "${TMP}/posted"
assert_eq "an installed plugin is sent" "0" "$(run "$(script_of plugin_share send)" DECREE_DATA_CLIENT=garage-box DECREE_DATA_MACHINE="$PLUGIN" \
    PLUGIN_SHARE_CALLBACK_GARAGE_BOX="${STUB}/cb/offer/home")"
tail -n +3 "${TMP}/posted" > "${TMP}/exported.md" 2>/dev/null
assert_eq "...as the file it was installed from" "$(cat "$W/.decree/plugins/${PLUGIN}.md")" "$(cat "${TMP}/exported.md")"
assert_eq "a machine no plugin installed is not sent" "1" "$(run "$(script_of plugin_share send)" DECREE_DATA_CLIENT=garage-box DECREE_DATA_MACHINE=no_such \
    PLUGIN_SHARE_CALLBACK_GARAGE_BOX="${STUB}/cb/offer/home")"
shape() { yq --front-matter=extract -o json -I0 '[.name, .machine, .scripts, .["x-exist-endpoints"]]' "$1" | jq -cS .; }   # key order aside
# Offered by another stack, it waits in ai/proposed/ for you.
cp "$(script_of plugin_offer offer)" "${TMP}/offer.sh"
{ printf -- '---\nmachine: plugin_offer\n---\n\n'; cat "${TMP}/exported.md"; } > "${TMP}/offer-msg.md"
rm -f "$W/ai/proposed/${PLUGIN}.md"; reset_emits
assert_eq "an offered plugin file is taken" "0" "$(run "${TMP}/offer.sh" DECREE_MESSAGE="${TMP}/offer-msg.md" DECREE_DATA_FROM=garage-box)"
assert_eq "...into ai/proposed/, as sent" "$(shape "${TMP}/exported.md")" "$(shape "$W/ai/proposed/${PLUGIN}.md" 2>/dev/null)"
assert_has "...and you are told it would replace yours" "$(cat "${TMP}"/emits/* 2>/dev/null)" "garage-box offers the machine ${PLUGIN}. It would replace the ${PLUGIN} you have."
assert_has "...and how to install it" "$(cat "${TMP}"/emits/* 2>/dev/null)" "mv ai/proposed/${PLUGIN}.md .decree/plugins/ && decree install ${PLUGIN}"
printf -- '---\nmachine: plugin_offer\n---\n\nsomething else entirely\n' > "${TMP}/offer-junk.md"
assert_eq "an offer that is not a plugin file fails" "1" "$(run "${TMP}/offer.sh" DECREE_MESSAGE="${TMP}/offer-junk.md" DECREE_DATA_FROM=garage-box)"
rm -f "$W/ai/proposed/"*.md
# Asked for no machine, a stack sends the list of its machines, and the asker's phone shows it.
: > "${TMP}/event"
assert_eq "a request for the list needs no yes" "0" "$(run "$(script_of plugin_share permit)" DECREE_DATA_CLIENT=garage-box DECREE_DATA_MACHINE= \
    PLUGIN_SHARE_CALLBACK_GARAGE_BOX="${STUB}/cb/offer/home" DECREE_EVENT_FILE="${TMP}/event")"
assert_eq "...and goes straight to send" "allowed" "$(cat "${TMP}/event")"
rm -f "${TMP}/posted"
assert_eq "the list is sent" "0" "$(run "$(script_of plugin_share send)" DECREE_DATA_CLIENT=garage-box DECREE_DATA_MACHINE= \
    PLUGIN_SHARE_CALLBACK_GARAGE_BOX="${STUB}/cb/offer/home" PLUGIN_SHARE_CALLBACK_GARAGE_BOX_TOKEN=s3 PLUGIN_SHARE_ALLOW=notify,${PLUGIN})"
assert_has "...to the client's callback, with its token" "$(head -2 "${TMP}/posted" 2>/dev/null)" "/cb/offer/home
Bearer s3"
assert_has "...naming each machine, free or asking, with what it does" "$(cat "${TMP}/posted" 2>/dev/null)" "- ${PLUGIN} (free): One mode per resource at a time"
assert_has "...one not shared freely asks" "$(cat "${TMP}/posted" 2>/dev/null)" "- note_watch (asks)"
{ printf -- '---\nmachine: plugin_offer\n---\n\n'; tail -n +3 "${TMP}/posted"; } > "${TMP}/list-msg.md"
reset_emits
assert_eq "a list offered back is taken" "0" "$(run "${TMP}/offer.sh" DECREE_MESSAGE="${TMP}/list-msg.md" DECREE_DATA_FROM=garage-box)"
assert_has "...to your phone, with the line that asks for one" "$(cat "${TMP}"/emits/* 2>/dev/null)" "- ${PLUGIN} (free)"
assert_has "...with the line that asks for one" "$(cat "${TMP}"/emits/* 2>/dev/null)" "--machine plugin_request --param from=garage-box --param machine=<name>"
assert_eq "...and nothing is proposed" "no" "$(ls "$W/ai/proposed/"*.md >/dev/null 2>&1 && echo yes || echo no)"
# plugin_request asks a peer for its list, or for one machine, at the peer's share endpoint.
REQ="$(script_of plugin_request request)"
rm -f "${TMP}/posted"
assert_eq "a stack asks a peer for a machine" "0" "$(run "$REQ" DECREE_DATA_FROM=garage-box DECREE_DATA_MACHINE="$PLUGIN" \
    PLUGIN_SHARE_NAME=home PLUGIN_PEER_GARAGE_BOX="${STUB}/cb/" PLUGIN_PEER_GARAGE_BOX_TOKEN=t0)"
assert_eq "...at its share endpoint, named as it knows this stack" "/cb/plugins/${PLUGIN}/share/home|Bearer t0" "$(head -2 "${TMP}/posted" 2>/dev/null | paste -sd'|')"
assert_eq "...or for its list" "0" "$(run "$REQ" DECREE_DATA_FROM=garage-box PLUGIN_SHARE_NAME=home PLUGIN_PEER_GARAGE_BOX="${STUB}/cb")"
assert_eq "...at the share endpoint without a machine" "/cb/plugins/share/home" "$(head -1 "${TMP}/posted" 2>/dev/null)"
assert_eq "without PLUGIN_SHARE_NAME it fails" "1" "$(run "$REQ" DECREE_DATA_FROM=garage-box PLUGIN_PEER_GARAGE_BOX="${STUB}/cb")"
assert_has "...saying what to set" "$(cat "${TMP}/last.log")" "set PLUGIN_SHARE_NAME"

echo ""; echo "=== sync ==="
# The repo's plugins dir is the one source: a project's plugins/ is what is on
# and what that needs, and decree installs it; a changed file is installed
# again, and decree archives a copy edited in place first; auto_update off only
# names it; one no longer wanted goes, its cron and lib with it, but not what is
# yours; a flow brings what it needs and its order files; decree 0.5's copies go.
PD="${TMP}/plugins"; mkdir -p "$PD"
mkplugin() {  # <name> <needs list> [script body]
    cat > "${PD}/$1.md" <<EOF
---
name: $1
x-exist-project: automation
needs: $2
machine:
  description: $1, for the test.
  initial: go
  states:
    go: { invoke: go, transitions: { done: done } }
    done: { final: true }
    failed: { final: true }
scripts:
  go.sh: |
    #!/usr/bin/env bash
    ${3:-echo $1}
---
# $1
EOF
}
mkplugin alpha '[beta]' 'echo | decree emit --machine beta'
mkplugin beta '[]'
mkplugin gamma '[]'
mkplugin delta '[]'
mkplugin hostonly '[]'; yq --front-matter=process -i '.["x-exist-project"] = "host"' "${PD}/hostonly.md"
# A cron of its own, a helper in lib, and a file that is yours once written.
yq --front-matter=process -i '.cron["gamma_hourly.md"] = "---\nmachine: gamma\ncron: \"0 * * * *\"\n---\n" | .["x-exist-lib"]["gamma/helper.sh"] = "echo helped\n" | .state["conf.txt"] = "shipped\n"' "${PD}/gamma.md"
S="${TMP}/sp"; mkdir -p "$S/.decree"
psync() {  # psync [name...]: one plugin_sync of the automation project; its output in $TMP/sync.log
    ( cd "$S" && PLUGINS_ON="$S/plugins.yml" bash -c 'source "$1"; shift; plugin_sync "$@"' \
        _ "${REPO_DIR}/automation/lib/plugin.sh" "$PD" automation "$@" ) > "${TMP}/sync.log" 2>&1
    echo $?
}
installed() { (cd "$S/.decree/machines" 2>/dev/null && ls -d -- */machine.yml 2>/dev/null | sed 's#/machine\.yml$##' | sort | paste -sd' '); }
copies() { (cd "$S/.decree" && find machines -type f | sort | xargs cksum); }
printf 'on: [alpha]\n' > "$S/plugins.yml"
assert_eq "a sync runs" "0" "$(psync)"
assert_eq "...installs what plugins.yml has on and what that needs, and nothing else" "alpha beta" "$(installed)"
assert_eq "...each as written" "echo beta" "$(tail -1 "$S/.decree/machines/beta/scripts/go.sh")"
assert_eq "...from its file in plugins/, which decree installs" "yes" "$(cmp -s "${PD}/beta.md" "$S/.decree/plugins/beta.md" && echo yes || echo no)"
before="$(copies)"
assert_eq "...and an unchanged one again changes nothing" "$before" "$(psync >/dev/null; copies)"
printf 'on: [alpha, gamma]\n' > "$S/plugins.yml"
psync >/dev/null
assert_eq "one turned on is installed" "alpha beta gamma" "$(installed)"
assert_eq "...with its cron" "gamma" "$(yq --front-matter=extract -r .machine "$S/.decree/machines/gamma/cron/gamma_hourly.md" 2>/dev/null)"
assert_eq "...and its lib, where its scripts reach it" "echo helped" "$(cat "$S/.decree/lib/gamma/helper.sh" 2>/dev/null)"
assert_eq "what is yours (state:) is written to its store, once" "shipped" "$(cat "$S/.decree/store/gamma/conf.txt" 2>/dev/null)"
assert_eq "...which is the machine's state/" "shipped" "$(cat "$S/.decree/machines/gamma/state/conf.txt" 2>/dev/null)"
echo mine > "$S/.decree/store/gamma/conf.txt"
yq --front-matter=process -i '.state["conf.txt"] = "shipped two\n"' "${PD}/gamma.md"
psync >/dev/null
assert_eq "...and never overwritten" "mine" "$(cat "$S/.decree/store/gamma/conf.txt")"
mkdir -p "$S/.decree/cron"; printf -- '---\nmachine: gamma\ncron: "* * * * *"\n---\n' > "$S/.decree/cron/mine.md"
assert_has "a cron file in .decree/cron/ is not read, and the sync says so" "$(psync >/dev/null; cat "${TMP}/sync.log")" ".decree/cron/ is not read"
rm -rf "$S/.decree/cron"
assert_eq "a name given that is tagged for another project is not installed" "alpha beta gamma" "$(psync hostonly >/dev/null; installed)"
# A flow: no machine, in plugins/flows/; it needs a machine, and an order file runs that machine once.
mkdir -p "${PD}/flows"
printf -- '---\nname: epsilon\nx-exist-project: automation\nx-exist-title: Epsilon\nx-exist-tagline: delta, set up once\nneeds:\n  - delta\n  - decree_order\norder:\n  epsilon-setup.md: |\n    ---\n    machine: delta\n    ---\n---\n' > "${PD}/flows/epsilon.md"
assert_eq "a flow brings the plugins it needs, decree's decree_order among them" "alpha beta decree_order delta gamma" "$(psync epsilon >/dev/null; installed)"
assert_eq "...as flow_<name>, whose order file is in" "delta" "$(yq --front-matter=extract -r .machine "$S/.decree/machines/flow_epsilon/order/epsilon-setup.md" 2>/dev/null)"
assert_has "...and queued to run now, not at the next start" "$(cat "${TMP}/sync.log")" "order files are queued to run"
psync >/dev/null
assert_eq "...and removed when nothing wants them" "alpha beta gamma" "$(installed)"
# One that extends decree's: its base, and what decree adds for that, come and go with it.
printf -- '---\nname: zeta\nextends: decree_develop\nx-exist-project: automation\nscripts:\n  gate.sh: |\n    echo pass > "$DECREE_EVENT_FILE"\n---\n' > "${PD}/zeta.md"
printf 'on: [alpha, gamma, zeta]\n' > "$S/plugins.yml"
assert_eq "one that extends decree's installs with its base and that base's needs" "alpha beta decree_develop decree_infra decree_order gamma zeta" "$(psync >/dev/null; installed)"
assert_eq "...its own file over the base's" 'echo pass > "$DECREE_EVENT_FILE"' "$(tail -1 "$S/.decree/machines/zeta/scripts/gate.sh" 2>/dev/null)"
printf 'on: [alpha, gamma]\n' > "$S/plugins.yml"
assert_eq "...and all of it goes with it, decree_order included" "alpha beta gamma" "$(psync >/dev/null; installed)"
rm -f "${PD}/zeta.md"
mkplugin beta '[]' 'echo beta two'
psync >/dev/null
assert_eq "a changed plugin is installed again" "echo beta two" "$(tail -1 "$S/.decree/machines/beta/scripts/go.sh")"
assert_eq "...without keeping a copy nobody edited" "" "$(ls "$S/.decree/archive/beta" 2>/dev/null)"
echo 'echo mine' >> "$S/.decree/machines/beta/scripts/go.sh"
mkplugin beta '[]' 'echo beta three'
psync >/dev/null
assert_eq "an edited copy is replaced" "echo beta three" "$(tail -1 "$S/.decree/machines/beta/scripts/go.sh")"
assert_has "...and decree archives it first" "$(cat "$S"/.decree/archive/beta/*.md 2>/dev/null)" "echo mine"
printf 'on: [alpha, gamma]\nauto_update: false\n' > "$S/plugins.yml"
mkplugin beta '[]' 'echo beta four'
psync >/dev/null
assert_eq "with auto_update off a change is not installed" "echo beta three" "$(tail -1 "$S/.decree/machines/beta/scripts/go.sh")"
assert_has "...only named" "$(cat "${TMP}/sync.log")" "beta has a new version"
printf 'on: [alpha]\n' > "$S/plugins.yml"
psync >/dev/null
assert_eq "one turned off again is removed" "alpha beta" "$(installed)"
assert_eq "...its cron and lib with it" "no" "$([[ -e "$S/.decree/machines/gamma/cron/gamma_hourly.md" || -e "$S/.decree/lib/gamma/helper.sh" ]] && echo yes || echo no)"
assert_eq "...but not what is yours" "mine" "$(cat "$S/.decree/store/gamma/conf.txt" 2>/dev/null)"
mkdir -p "$S/.decree/machines/mine"
printf 'name: mine\ndescription: Mine.\ninitial: done\nstates:\n  done: { final: true }\n  failed: { final: true }\n' > "$S/.decree/machines/mine/machine.yml"
psync >/dev/null
assert_eq "a machine of yours is never touched" "yes" "$([[ -e "$S/.decree/machines/mine/machine.yml" ]] && echo yes || echo no)"
# decree 0.5's copies: a plugin's goes (the plugin is installed again), one of yours moves to its folder.
printf 'name: gamma\n' > "$S/.decree/machines/gamma.yml"
printf 'name: old\ndescription: Old.\ninitial: done\nstates:\n  done: { final: true }\n  failed: { final: true }\n' > "$S/.decree/machines/old.yml"
psync >/dev/null
assert_eq "decree 0.5's copy of a plugin goes" "no" "$([[ -e "$S/.decree/machines/gamma.yml" ]] && echo yes || echo no)"
assert_eq "...and a machine of yours moves to machines/<name>/" "yes" "$([[ -f "$S/.decree/machines/old/machine.yml" && ! -e "$S/.decree/machines/old.yml" ]] && echo yes || echo no)"
( cd "$S" && decree export --no-color alpha ) >/dev/null 2>&1
assert_eq "decree export keeps existential's keys" "automation" "$(yq --front-matter=extract -r '.["x-exist-project"]' "$S/.decree/plugins/alpha.md")"


# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→exit path is proven (run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
