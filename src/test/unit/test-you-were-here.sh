#!/usr/bin/env bash
# test-you-were-here.sh — the "you were here" digest, automation/scripts/you_were_here.sh.
#
# Three digests on three days over one workspace, with `decree emit` stubbed so a push
# is a file, and one local server that is both the feed and the model:
#
#   day 1   model unreachable: the attention item is under Waiting on you, the
#           machine that succeeded under Holding steady, and the push has both;
#           Where you left off shows each session's last prompt, by project;
#           no feeds.md, so no feeds section; the day's archive is written
#   day 1   again with nothing changed: the note is refreshed, nothing is pushed
#   day 2   model up, feeds.md present: The picture and a feed reason appear; the
#           checkbox ticked since day 1 is under Done; day 1's archive is unchanged
#   day 3   a feed item shown on day 2 is not shown again
#   learn   Worth learning: no model, no section; the model's subject is looked up
#           on (stubbed) Wikipedia; an article shown before or linked from a note
#           is skipped
#   wiring  the cron template is seeded and POST /you-were-here routes here
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

# ── The stub: GET /feed.xml is $TMP/feed.xml, POST /v1/chat/completions is $TMP/reply
cat > "${TMP}/stub.js" <<'EOF'
const http = require("node:http");
const fs = require("node:fs");
const dir = process.argv[2];
const srv = http.createServer((req, res) => {
  req.resume();
  req.on("end", () => {
    if (req.url === "/feed.xml") { res.end(fs.readFileSync(`${dir}/feed.xml`)); return; }
    // Wikipedia: search answers the same three titles, best first; a summary is "About <title>."
    if (req.url.startsWith("/w/api.php?")) {
      res.end(JSON.stringify({ query: { search: ["Drip irrigation", "Irrigation", "Rain barrel"].map((title) => ({ title })) } }));
      return;
    }
    if (req.url.startsWith("/api/rest_v1/page/summary/")) {
      res.end(JSON.stringify({ extract: `About ${decodeURIComponent(req.url.split("/").pop()).replace(/_/g, " ")}.` }));
      return;
    }
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

feed() {   # feed <title>...: an RSS feed of those items, linked https://example.test/<title>
    { echo '<rss><channel>'
      for t in "$@"; do echo "<item><title>${t}</title><link>https://example.test/${t}</link><description>${t//-/ }</description></item>"; done
      echo '</channel></rss>'; } > "${TMP}/feed.xml"
}

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

# ── The workspace ─────────────────────────────────────────────────────────────
W="${TMP}/workspace"
mkdir -p "$W"/.decree/{attention,runs/20260930T100000.000000Z-aaaaaa,cron,machines} "$W"/notes "$W"/.capture
cat > "$W/.decree/attention/20260930T110000.000000Z-bbbbbb.md" <<'EOF'
---
kind: run
run: 20260930T110000.000000Z-bbbbbb
machine: gmail
message: gmail.md
status: failed
state: fetch
since: 2026-09-30T11:00:05Z
holds: false
---
The run failed.
EOF
cat > "$W/.decree/runs/20260930T100000.000000Z-aaaaaa/events.jsonl" <<'EOF'
{"type":"transition","machine":"newsletter","trigger":"cron","run_id":"20260930T100000.000000Z-aaaaaa","from":null,"to":"gather","ts":"2026-09-30T10:00:00.000Z"}
{"type":"run_finished","machine":"newsletter","trigger":"cron","run_id":"20260930T100000.000000Z-aaaaaa","state":"done","ts":"2026-09-30T10:01:00.000Z"}
EOF
printf -- '---\ncron: "0 7 * * MON"\nmachine: newsletter\n---\n' > "$W/.decree/cron/newsletter.md"
printf '# Garden plan\n\n- [ ] order the raised beds\n- [ ] compost delivery\n' > "$W/notes/garden.md"
printf '%s\n' '{"ts":"2026-09-30T20:00:00Z","source":"claude-code","context":"/workspace/garden","text":"sketch the irrigation for the raised beds"}' \
    '{"ts":"2026-09-30T20:01:00Z","source":"claude-code","context":"/workspace/shed","session":"s1","text":"list the shelving parts"}' \
    '{"ts":"2026-09-30T20:02:00Z","source":"claude-code","context":"/workspace/shed","session":"s2","text":"price the roof panels"}' \
    '{"ts":"2026-09-30T20:03:00Z","source":"claude-code","context":"/workspace/shed","session":"s1","text":"order the brackets"}' \
    > "$W/.capture/2026-09-test.jsonl"
# Fixed mtimes: the clock is pinned by DIGEST_NOW, so files must not look newer than it.
find "$W" -type f -exec touch -d 2026-09-30T12:00:00Z {} +

# run_digest <now>: one run of the machine's script, as decree runs it, in its own run dir.
run_digest() {
    local run="${TMP}/rundirs/$1"
    mkdir -p "$run"
    ( cd "$W" && PATH="${TMP}/bin:$(dirname "$TSX"):${PATH}" TZ=UTC PUSHES="${TMP}/pushes" \
        DECREE_LIB="${REPO_DIR}/automation/lib" DECREE_STORE="${TMP}/store" DECREE_RUN_DIR="$run" \
        DECREE_DATA_WORKSPACE="$W" DECREE_DATA_NTFY_TOPIC=exist DECREE_DATA_NOTE_LINK="" EXIST_TAILNET_NAME="${TAILNET_UNDER_TEST:-}" \
        EXIST_MODEL_URL="${MODEL_URL_UNDER_TEST}" EXIST_MODEL_CHAT=test-model DIGEST_NOW="$1" \
        WIKIPEDIA_URL="http://127.0.0.1:${PORT}" \
        bash "${REPO_DIR}/automation/scripts/you_were_here.sh" ) > "${run}.log" 2>&1
    echo $?
}
NOTE="$W/ai/you-were-here.md"
DAY1="$W/ai/you-were-here/2026/2026-10-01.md"
DAY2="$W/ai/you-were-here/2026/2026-10-02.md"

# ── day 1: the model is unreachable ───────────────────────────────────────────
MODEL_URL_UNDER_TEST="http://127.0.0.1:9/v1"
assert_eq "day 1 runs with the model unreachable" "0" "$(run_digest 2026-10-01T07:00:00Z)"
assert_has "the attention item is under Waiting on you" "$(section "$NOTE" "Waiting on you")" "**gmail** is failed in fetch"
assert_has "the machine that succeeded is under Holding steady" "$(section "$NOTE" "Holding steady")" "**newsletter**: last run succeeded"
assert_has "the schedule is under Holding steady" "$(section "$NOTE" "Holding steady")" "Schedules active: [newsletter]"
assert_has "the attention link is rebased for ai/" "$(section "$NOTE" "Waiting on you")" "](../.decree/attention/20260930T110000.000000Z-bbbbbb.md)"
assert_has "the captured thread is under Where you left off" "$(section "$NOTE" "Where you left off")" "**garden**: 1 prompt"
LEFT="$(section "$NOTE" "Where you left off")"
assert_has "a sessionless line is its context's last prompt" "$LEFT" 'last: "sketch the irrigation for the raised beds"'
assert_has "the project counts every session's prompts" "$LEFT" "**shed**: 3 prompts"
assert_has "...and shows one session's last prompt" "$LEFT" 'last: "order the brackets"'
assert_has "...and the other's" "$LEFT" 'last: "price the roof panels"'
assert_lacks "...but not a session's earlier prompt" "$LEFT" "list the shelving parts"
assert_has "the touched note lists its open checkboxes" "$(section "$NOTE" "Everything else")" "- [ ] order the raised beds"
assert_lacks "no model, no picture" "$(cat "$NOTE")" "## The picture"
assert_lacks "no model, no next thing" "$(cat "$NOTE")" "## One next thing"
assert_lacks "no feeds.md, no feeds section" "$(cat "$NOTE")" "## From your feeds"
assert_lacks "no model, no Worth learning" "$(cat "$NOTE")" "## Worth learning"
assert_eq "one push" "1" "$(pushes)"
PUSH="$(cat "${TMP}/pushes/1")"
assert_has "the push carries the attention item" "$PUSH" "**gmail** is failed in fetch"
assert_has "the push carries the steady machine" "$PUSH" "**newsletter**: last run succeeded"
assert_has "the push ends with the note" "$PUSH" "Full digest: workspace/ai/you-were-here.md"
assert_lacks "the push leaves out Everything else" "$PUSH" "Everything else"
assert_has "the push goes to notify" "$(cat "${TMP}/pushes/1.args")" "emit --machine notify --param ntfy_topic=exist"
assert_eq "the day's archive is written" "yes" "$([[ -f "$DAY1" ]] && echo yes)"
assert_has "the archive has a Done section" "$(cat "$DAY1")" "## Done"
assert_has "the archive's links are rebased for its depth" "$(cat "$DAY1")" "](../../../.decree/attention/"
assert_lacks "the first digest calls nothing that was already there done" "$(section "$DAY1" "Done")" "New note"

# ── day 1 again: nothing changed ──────────────────────────────────────────────
assert_eq "a second run the same day succeeds" "0" "$(run_digest 2026-10-01T09:00:00Z)"
assert_eq "nothing changed, so nothing is pushed" "1" "$(pushes)"
assert_has "...and the note is still refreshed" "$(cat "${TMP}/rundirs/2026-10-01T09:00:00Z.log")" "write: ai/you-were-here.md"
cp "$DAY1" "${TMP}/day1.md"

# ── day 2: the model answers, feeds.md exists, a checkbox was ticked, Tailscale is up ──
TAILNET_UNDER_TEST=box.tail1234.ts.net
MODEL_URL_UNDER_TEST="http://127.0.0.1:${PORT}/v1"
printf '# Feeds\n\n- http://127.0.0.1:%s/feed.xml\n' "$PORT" > "$W/notes/feeds.md"
feed raised-beds-irrigation knitting-patterns stock-market-news
jq -n '{picture: "The garden is [moving](notes/garden.md); gmail [needs a look](.decree/attention/20260930T110000.000000Z-bbbbbb.md).",
        next: "Retry [gmail](.decree/attention/20260930T110000.000000Z-bbbbbb.md).",
        reasons: {"https://example.test/raised-beds-irrigation": "You were sketching irrigation for the beds."},
        learn: "drip irrigation"} | tostring' -r > "${TMP}/reply"
sed -i 's/- \[ \] compost delivery/- [x] compost delivery/' "$W/notes/garden.md"
printf '%s\n' '{"ts":"2026-10-02T06:00:00Z","source":"opencode","context":"/workspace/shed","session":"s3","text":"measure the door frame"}' >> "$W/.capture/2026-09-test.jsonl"
touch -d 2026-10-01T12:00:00Z "$W/notes/garden.md" "$W/notes/feeds.md"
assert_eq "day 2 runs" "0" "$(run_digest 2026-10-02T07:00:00Z)"
assert_has "the model wrote The picture" "$(section "$NOTE" "The picture")" "The garden is [moving](../notes/garden.md)"
assert_has "the model wrote One next thing" "$(section "$NOTE" "One next thing")" "Retry [gmail]"
FEEDS="$(section "$NOTE" "From your feeds")"
assert_has "feeds.md present, feeds section present" "$(cat "$NOTE")" "## From your feeds"
assert_has "the related item comes with its reason" "$FEEDS" "[raised-beds-irrigation](https://example.test/raised-beds-irrigation): You were sketching irrigation"
assert_eq "three items shown" "3" "$(grep -c '^- ' <<<"$FEEDS")"
LEARN="$(section "$NOTE" "Worth learning")"
assert_has "Worth learning links the article Wikipedia found for the model's subject" "$LEARN" "[Drip irrigation](https://en.wikipedia.org/wiki/Drip_irrigation): About Drip irrigation."
assert_has "...and says what it is for" "$LEARN" "For what you've been looking into: drip irrigation."
assert_eq "day 2 is pushed" "2" "$(pushes)"
assert_has "the push starts with The picture" "$(head -n1 "${TMP}/pushes/2")" "## The picture"
assert_lacks "the push leaves out Worth learning" "$(cat "${TMP}/pushes/2")" "Worth learning"
assert_has "the push shows link text, not paths" "$(cat "${TMP}/pushes/2")" "The garden is moving;"
assert_has "with a tailnet name, the push links to code-server there" "$(cat "${TMP}/pushes/2")" "Full digest: ai/you-were-here.md, in https://box.tail1234.ts.net"
assert_has "the ticked checkbox is under Done" "$(section "$DAY2" "Done")" "Ticked: compost delivery"
assert_has "what you worked on today is under Done, with its source" "$(section "$DAY2" "Done")" "Worked on **shed**: 1 prompt via opencode"
assert_has "feeds.md is a new note under Done" "$(section "$DAY2" "Done")" "New note: [notes/feeds.md]"
assert_eq "day 1's archive is unchanged" "same" "$(cmp -s "$DAY1" "${TMP}/day1.md" && echo same)"
assert_eq "both days are archived" "2026-10-01.md 2026-10-02.md" "$(ls "$W/ai/you-were-here/2026" | tr '\n' ' ' | sed 's/ $//')"

# ── day 3: an item shown on day 2, or already linked from a note, is not shown ─
feed raised-beds-irrigation knitting-patterns stock-market-news compost-tea worm-farm
printf '# Reading\n\n- https://example.test/worm-farm, watched it, worth redoing the bins\n- read https://en.wikipedia.org/wiki/Irrigation.\n' > "$W/notes/reading.md"
assert_eq "day 3 runs" "0" "$(run_digest 2026-10-03T07:00:00Z)"
FEEDS="$(section "$NOTE" "From your feeds")"
assert_has "the new item is shown" "$FEEDS" "compost-tea"
assert_lacks "an item already shown is not shown again" "$FEEDS" "raised-beds-irrigation"
assert_lacks "...nor any other one" "$FEEDS" "knitting-patterns"
assert_lacks "an item already linked from a note is not shown" "$FEEDS" "worm-farm"
LEARN="$(section "$NOTE" "Worth learning")"
assert_lacks "an article already suggested is not suggested again" "$LEARN" "Drip_irrigation"
assert_lacks "an article a note links to is skipped" "$LEARN" "wiki/Irrigation)"
assert_has "...so the next one Wikipedia found is suggested" "$LEARN" "[Rain barrel](https://en.wikipedia.org/wiki/Rain_barrel)"
assert_eq "the archive is per day" "3" "$(find "$W/ai/you-were-here" -name '*.md' | wc -l | tr -d ' ')"

# ── wiring ────────────────────────────────────────────────────────────────────
assert_eq "the cron template runs this machine" "you_were_here" \
    "$(awk '/^machine:/{print $2; exit}' "${REPO_DIR}/flows/you-were-here/cron/you-were-here.md")"
assert_has "it is a default flow, on in every install" "$(cat "${REPO_DIR}/flows/you-were-here/flow.md")" "default: true"
assert_eq "POST /you-were-here queues this machine" "you_were_here" \
    "$(awk '/- path: \/you-were-here$/{f=1; next} f && /machine:/{print $2; exit}' "${REPO_DIR}/automation/decree-go-rest.yml")"
assert_lacks "no second feed parser" "$(cat "${REPO_DIR}/automation/lib/you-were-here/digest.ts")" "<item"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]] || { printf '  - %s\n' "${FAIL_NAMES[@]}"; for l in "${TMP}"/rundirs/*.log; do echo "--- $l"; cat "$l"; done; exit 1; }
