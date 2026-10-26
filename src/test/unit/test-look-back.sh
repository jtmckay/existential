#!/usr/bin/env bash
# test-look-back.sh — the look back, automation/scripts/look_back.sh.
#
# One archive of hand-written day notes, in the shape lib/you-were-here/digest.ts
# writes them, across July to September 2026 plus a day either side; `decree emit`
# stubbed so a push is a file, and a local server as the model:
#
#   quarter   model unreachable: the file exists, every Highlights item links to a
#             day note in the range, nothing outside it shows, the data sections alone
#   scope     scope.md is created on first use; a work scope naming one project
#             gives only that project's items
#   Sunday    period_end_only: the week's look back lands next to the day notes on
#             Sunday, and nothing is written on Saturday
#   month     the same at month-end: nothing on the 30th of July, the month on the 31st
#   year      the default range is the year to date, read from the week and month
#             look backs plus the day notes they do not cover; the model writes In short
#   archive   no day note is ever rewritten
#   wiring    the cron templates and POST /look-back route here
#
# Everything is written under a temp dir, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
TSX="$(command -v tsx || echo /opt/decree/node_modules/.bin/tsx)"

for _t in node jq curl "$TSX"; do
    if ! command -v "$_t" >/dev/null 2>&1; then
        echo "skipped — ${_t} not available (run inside existential-adhoc)"
        exit 0
    fi
done

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()    { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has()   { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }
assert_lacks() { if [[ "$2" != *"$3"* ]]; then _ok "$1"; else _fail "$1" "found: $3"; fi; }
# section <file> <heading>: the lines under "## <heading>", up to the next "## ".
section() { awk -v h="## $2" '$0 == h {f=1; next} f && /^## /{exit} f' "$1"; }

TMP="$(mktemp -d)"
STUB_PID=""
trap '[ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

# ── The model: POST /v1/chat/completions answers $TMP/reply ──────────────────
cat > "${TMP}/stub.js" <<'EOF'
const http = require("node:http");
const fs = require("node:fs");
const dir = process.argv[2];
const srv = http.createServer((req, res) => {
  req.resume();
  req.on("end", () => {
    if (req.method === "POST" && req.url === "/v1/chat/completions") {
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ choices: [{ message: { content: fs.readFileSync(`${dir}/reply`, "utf8") } }] }));
      return;
    }
    res.statusCode = 404; res.end();
  });
});
srv.listen(0, "127.0.0.1", () => fs.writeFileSync(`${dir}/port`, String(srv.address().port)));
EOF
node "${TMP}/stub.js" "$TMP" & STUB_PID=$!
for _ in $(seq 50); do [[ -s "${TMP}/port" ]] && break; sleep 0.1; done
PORT="$(cat "${TMP}/port")"

# `decree emit` as a file: each push is $TMP/pushes/<n>, its args in <n>.args.
mkdir -p "${TMP}/bin" "${TMP}/pushes"
cat > "${TMP}/bin/decree" <<'EOF'
#!/usr/bin/env bash
n=$(( $(find "$PUSHES" -name '*.args' | wc -l) + 1 ))
printf '%s\n' "$*" > "${PUSHES}/${n}.args"
cat > "${PUSHES}/${n}"
EOF
chmod +x "${TMP}/bin/decree"
pushes() { find "${TMP}/pushes" -name '*.args' | wc -l | tr -d ' '; }

# ── The archive ───────────────────────────────────────────────────────────────
W="${TMP}/workspace"
A="$W/ai/you-were-here"
# daynote <date> <decisions line or ""> <Done lines...>: an archived day, links as the digest rebases them.
daynote() {
    local d="$1" decision="$2"; shift 2
    mkdir -p "$A/${d:0:4}"
    { echo "# You were here, ${d}"; echo
      echo "## Waiting on you"; echo; echo "Nothing is waiting on you."; echo
      echo "## Everything else"; echo
      echo "### Decisions"; echo; echo "${decision:-No new decisions in notes/decisions/.}"; echo
      echo "### Notes touched"; echo; echo "None."; echo
      echo "## Done"; echo
      printf -- '- %s\n' "$@"; } > "$A/${d:0:4}/${d}.md"
}
R='../../../'
daynote 2026-06-30 "" "Ticked: sweep the attic ([note](${R}notes/shed/plan.md))"
daynote 2026-07-06 "- [Use cedar](${R}notes/decisions/cedar.md)" \
    "Ticked: order the brackets ([note](${R}notes/shed/plan.md))" \
    "New note: [notes/garden/beds.md](${R}notes/garden/beds.md)" \
    "**gmail_sync** finished: done ([run](${R}.decree/runs/r1/message.md))" \
    "Worked on **shed**: 3 prompts via claude-code ([capture](${R}.capture/2026-07-box.jsonl))" \
    "Worked on **garden**: 1 prompt via opencode ([capture](${R}.capture/2026-07-box.jsonl))"
daynote 2026-08-12 "- [Use cedar](${R}notes/decisions/cedar.md)" \
    "Ticked: water the beds ([note](${R}notes/garden/beds.md))" \
    "New machine: **look_back** ([machine](${R}.decree/machines/look_back.yml))" \
    "Migration landed: 012-look-back.md ([run](${R}.decree/runs/r2/message.md))" \
    "Worked on **shed**: 2 prompts via claude-code ([capture](${R}.capture/2026-08-box.jsonl))"
daynote 2026-09-14 "" \
    "Ticked: hang the door ([note](${R}notes/shed/plan.md))" \
    "**gmail_sync** finished: failed ([run](${R}.decree/runs/r3/message.md))" \
    "Worked on **shed**: 1 prompt via claude-code ([capture](${R}.capture/2026-09-box.jsonl))"
daynote 2026-10-01 "" "Ticked: paint the shed ([note](${R}notes/shed/plan.md))"
SUMS="$(cd "$A" && find . -name '20*-*-*.md' ! -name 'look-back-*' -exec md5sum {} + | sort)"

# run_lb <now> [key=value...]: one run of the machine's script, as decree runs it,
# with the machine's data defaults and these params.
run_lb() {
    local now="$1"; shift
    local run; run="$(mktemp -d "${TMP}/run.XXXXXX")"; echo "$run" > "${TMP}/last"
    local -A p=([period]=year [from]="" [to]="" [scope]=all [period_end_only]=false)
    for kv in "$@"; do p[${kv%%=*}]="${kv#*=}"; done
    ( cd "$W" && PATH="${TMP}/bin:$(dirname "$TSX"):${PATH}" TZ=UTC PUSHES="${TMP}/pushes" \
        DECREE_LIB="${REPO_DIR}/automation/lib" DECREE_RUN_DIR="$run" \
        DECREE_DATA_WORKSPACE="$W" DECREE_DATA_NTFY_TOPIC=exist DECREE_DATA_PERIOD="${p[period]}" \
        DECREE_DATA_FROM="${p[from]}" DECREE_DATA_TO="${p[to]}" DECREE_DATA_SCOPE="${p[scope]}" \
        DECREE_DATA_PERIOD_END_ONLY="${p[period_end_only]}" \
        EXIST_MODEL_URL="${MODEL_URL_UNDER_TEST}" EXIST_MODEL_CHAT=test-model LOOK_BACK_NOW="$now" \
        bash "${REPO_DIR}/automation/scripts/look_back.sh" ) > "${run}.log" 2>&1
    echo $?
}
lastlog() { cat "$(cat "${TMP}/last").log"; }

# ── the quarter, model unreachable ────────────────────────────────────────────
MODEL_URL_UNDER_TEST="http://127.0.0.1:9/v1"
Q="$A/2026/look-back-2026-07-01-2026-09-30.md"
assert_eq "a look back for the quarter runs" "0" "$(run_lb 2026-10-02T09:00:00Z period=quarter to=2026-09-30)"
assert_eq "its file exists" "yes" "$([[ -f "$Q" ]] && echo yes)"
HL="$(section "$Q" "Highlights")"
_links="$(grep '^- ' <<<"$HL" | grep -o '](\.\./[0-9]*/[0-9-]*\.md)' | sed 's/^](//; s/)$//')"
assert_eq "every Highlights item links to a day note" "$(grep -c '^- ' <<<"$HL")" "$(grep -c . <<<"$_links")"
_bad=""
while read -r l; do
    [[ -f "$A/2026/$l" && "$(basename "$l" .md)" > 2026-06-30 && "$(basename "$l" .md)" < 2026-10-01 ]] || _bad+="$l "
done <<<"$_links"
assert_eq "...that exists and is in the range" "" "$_bad"
assert_has "a ticked checkbox is a highlight, grouped by its project" "$HL" "### shed"
assert_has "...with its day" "$HL" "Ticked: hang the door ([2026-09-14](../2026/2026-09-14.md))"
assert_has "a landed migration is a highlight" "$HL" "Migration landed: 012-look-back.md"
assert_lacks "a day before the range is left out" "$(cat "$Q")" "sweep the attic"
assert_lacks "a day after the range is left out" "$(cat "$Q")" "paint the shed"
assert_has "a project on three days is a theme" "$(section "$Q" "Themes")" "**shed**: 3 days, 6 prompts"
DEC="$(section "$Q" "Decisions made")"
assert_has "a decision note is a decision" "$DEC" "Decision: Use cedar ([2026-07-06](../2026/2026-07-06.md))"
assert_eq "...once, though two days list it" "1" "$(grep -c 'Use cedar' <<<"$DEC")"
assert_has "a landed machine is a decision" "$DEC" "New machine: look_back"
NUM="$(section "$Q" "By the numbers")"
assert_has "the numbers count the days" "$NUM" "Days recorded: 3"
assert_has "...and the prompts" "$NUM" "Prompts: 7"
assert_has "...and the runs" "$NUM" "Runs finished: 2 (1 not done)"
assert_lacks "no model, no In short" "$(cat "$Q")" "## In short"
assert_eq "one push" "1" "$(pushes)"
assert_has "the push goes to notify" "$(cat "${TMP}/pushes/1.args")" "emit --machine notify --param ntfy_topic=exist"
assert_has "the push points at the file" "$(cat "${TMP}/pushes/1")" "workspace/ai/you-were-here/2026/look-back-2026-07-01-2026-09-30.md"

# ── scope ─────────────────────────────────────────────────────────────────────
assert_has "scope.md is created on first use" "$(cat "$A/scope.md")" "## Projects"
printf '# Look back scope\n\n## Projects\n\n- shed\n\n## Folders\n\n## Sources\n' > "$A/scope.md"
QW="$A/2026/look-back-2026-07-01-2026-09-30-work.md"
assert_eq "a work look back runs" "0" "$(run_lb 2026-10-02T09:00:00Z period=quarter to=2026-09-30 scope=work)"
assert_eq "it has its own file" "yes" "$([[ -f "$QW" ]] && echo yes)"
assert_eq "...and the everything one is untouched" "yes" "$(grep -q 'water the beds' "$Q" && echo yes)"
assert_eq "it has only that project's highlights" "### shed" "$(section "$QW" "Highlights" | grep '^### ')"
assert_has "...all of them" "$(section "$QW" "Highlights")" "order the brackets"
assert_lacks "no other project's item" "$(cat "$QW")" "water the beds"
assert_lacks "...nor the stack's" "$(cat "$QW")" "012-look-back.md"
assert_lacks "...nor its decisions" "$(cat "$QW")" "Use cedar"
assert_has "only that project's prompts are counted" "$(section "$QW" "By the numbers")" "Prompts: 6"
printf '# Look back scope\n\n## Projects\n\n## Folders\n\n- notes/garden/\n\n## Sources\n\n- `opencode`\n' > "$A/scope.md"
run_lb 2026-10-02T09:00:00Z period=quarter to=2026-09-30 scope=work >/dev/null
assert_has "a scope folder matches by path" "$(section "$QW" "Highlights")" "water the beds"
assert_has "a scope source matches what was captured from it" "$(section "$QW" "By the numbers")" "Prompts: 1"
assert_lacks "...and nothing else" "$(cat "$QW")" "hang the door"

# ── Sunday and month-end ──────────────────────────────────────────────────────
N="$(pushes)"
assert_eq "on a Saturday the weekly run exits 0" "0" "$(run_lb 2026-09-19T21:00:00Z period=week period_end_only=true)"
assert_eq "...and writes nothing" "" "$(find "$A" -name 'look-back-2026-09-14-*')"
assert_eq "...and pushes nothing" "$N" "$(pushes)"
assert_eq "on Sunday the weekly run runs" "0" "$(run_lb 2026-09-20T21:00:00Z period=week period_end_only=true)"
assert_eq "that week's look back is next to the day notes" "yes" "$([[ -f "$A/2026/look-back-2026-09-14-2026-09-20.md" ]] && echo yes)"
assert_has "...with that week's day" "$(cat "$A/2026/look-back-2026-09-14-2026-09-20.md")" "hang the door"
assert_eq "on the 30th of July the monthly run writes nothing" "0" "$(run_lb 2026-07-30T21:00:00Z period=month period_end_only=true)"
assert_eq "...nothing" "" "$(find "$A" -name 'look-back-2026-07-01-2026-07-30.md')"
run_lb 2026-07-31T21:00:00Z period=month period_end_only=true >/dev/null
run_lb 2026-08-31T21:00:00Z period=month period_end_only=true >/dev/null
assert_eq "on the 31st the month's look back is written" "yes" "$([[ -f "$A/2026/look-back-2026-07-01-2026-07-31.md" && -f "$A/2026/look-back-2026-08-01-2026-08-31.md" ]] && echo yes)"

# ── the year, from the look backs ─────────────────────────────────────────────
# Mark July's look back, so its items can only have come from it, not from the day note.
sed -i 's/order the brackets/order the brackets (via July)/g' "$A/2026/look-back-2026-07-01-2026-07-31.md"
MODEL_URL_UNDER_TEST="http://127.0.0.1:${PORT}/v1"
jq -n '{summary: "A summer of [shed work](../2026/2026-09-14.md)."} | tostring' -r > "${TMP}/reply"
Y="$A/2026/look-back-2026-01-01-2026-10-02.md"
assert_eq "the default look back runs" "0" "$(run_lb 2026-10-02T09:00:00Z)"
assert_eq "it is the year to date" "yes" "$([[ -f "$Y" ]] && echo yes)"
assert_has "it reads the week and month look backs and the day notes they leave" "$(lastlog)" "from 3 look backs and 2 day notes"
assert_has "a month comes from its look back" "$(cat "$Y")" "order the brackets (via July)"
assert_has "a day outside every look back comes from its day note" "$(cat "$Y")" "sweep the attic"
assert_has "...and so does one past the last" "$(cat "$Y")" "paint the shed"
assert_has "the days add up" "$(section "$Y" "By the numbers")" "Days recorded: 5"
assert_has "the model wrote In short" "$(section "$Y" "In short")" "A summer of [shed work](../2026/2026-09-14.md)."

# ── the archive ───────────────────────────────────────────────────────────────
assert_eq "no day note was rewritten" "$SUMS" "$(cd "$A" && find . -name '20*-*-*.md' ! -name 'look-back-*' -exec md5sum {} + | sort)"
assert_eq "a bad date fails the run" "1" "$(run_lb 2026-10-02T09:00:00Z from=2026-13-01)"

# ── wiring ────────────────────────────────────────────────────────────────────
cron() { awk -v k="$2:" '$1 == k {print $2; exit}' "${REPO_DIR}/flows/look-back/cron/$1"; }
assert_eq "the weekly cron runs this machine" "look_back" "$(cron look-back-weekly.md machine)"
assert_eq "...for the week" "week" "$(cron look-back-weekly.md period)"
assert_eq "the monthly cron runs this machine" "look_back" "$(cron look-back-monthly.md machine)"
assert_eq "...only at month-end" "true" "$(cron look-back-monthly.md period_end_only)"
assert_has "both are a default flow, on in every install" "$(cat "${REPO_DIR}/flows/look-back/flow.md")" "default: true"
assert_eq "POST /look-back queues this machine" "look_back" \
    "$(awk '/- path: \/look-back$/{f=1; next} f && /machine:/{print $2; exit}' "${REPO_DIR}/automation/decree-go-rest.yml")"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]] || { printf '  - %s\n' "${FAIL_NAMES[@]}"; for l in "${TMP}"/run.*.log; do echo "--- $l"; cat "$l"; done; exit 1; }
