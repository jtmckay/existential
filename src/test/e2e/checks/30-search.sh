#!/usr/bin/env bash
# e2e_search — a note written now is findable now, from every client.
#
# Staged into the clone's scripts/ by e2e.sh, with 30-search.yml as its machine.
# Runs inside the `automation` daemon, which writes /workspace and reaches qmd
# over the exist bridge. Every write lands in the disposable e2e clone.
set -euo pipefail

WS="${E2E_WORKSPACE:-/workspace}"
QMD="${QMD_URL:-http://qmd:8181}"
TOKEN="kx$(date +%s%N)"
NOTE="e2e-search/kayak-${TOKEN}.md"
# A second note on another subject, so "found by meaning" has to beat it: in a
# near-empty workspace the nearest note is trivially the only one.
OTHER="e2e-search/sourdough-${TOKEN}.md"

say()  { printf '  %s\n' "$*"; }
# stdout, not stderr: the run's log keeps stdout, so the reason is in the evidence.
fail() { printf '  FAIL  %s\n' "$*"; exit 1; }

until_ok() {  # <what> <seconds> <command...>
    local what="$1" timeout="$2"; shift 2
    local deadline=$(( SECONDS + timeout ))
    until "$@" >/dev/null 2>&1; do
        [ "$SECONDS" -lt "$deadline" ] || fail "${what}: not within ${timeout}s"
        sleep 3
    done
    say "ok    ${what} ($(( timeout - (deadline - SECONDS) ))s)"
}

query() {  # <searches json> → result files
    curl -fsS --max-time 60 "$QMD/query" -H 'Content-Type: application/json' \
        -d "{\"searches\": $1, \"limit\": 5, \"rerank\": false}" | jq -r '.results[].file'
}
mcp() {  # <method> <params json> → the JSON-RPC result
    curl -fsS --max-time 60 "$QMD/mcp" -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}" | sed -n 's/^data: //p' | jq -c '.result'
}
found_lex() { query "[{\"type\":\"lex\",\"query\":\"${TOKEN}\"}]" | grep -q "kayak-${TOKEN}"; }
embedded()  { [ "$(mcp tools/call '{"name":"status","arguments":{}}' | jq -r '.structuredContent.needsEmbedding')" = 0 ]; }
top_vec() {  # <question> <file that must rank first>
    [[ "$(query "$(jq -nc --arg q "$1" '[{type:"vec",query:$q}]')" | head -1)" == *"$2" ]]
}
found_vec() {
    top_vec "when does the paddling licence for the boat need renewing, and where" "kayak-${TOKEN}.md" &&
    top_vec "how long should the bread dough rise before it goes in the oven" "sourdough-${TOKEN}.md"
}

mkdir -p "$WS/e2e-search"
cat > "$WS/$NOTE" <<NOTE
# Kayak

River permit ${TOKEN}. It is renewed every April at the ranger station by the
north trailhead, and the sticker goes on the left side of the hull.
NOTE
cat > "$WS/$OTHER" <<NOTE
# Sourdough

Feed the starter the night before. The dough proves for four hours at room
temperature, then bakes at 230 °C in the cast-iron pot, lid on for twenty minutes.
NOTE
say "wrote $NOTE and $OTHER"

# One refresh is QMD_REFRESH_SECONDS (60 by default); two is the most it may take.
until_ok "found by keyword" 150 found_lex
# The first boot downloads the embedding model before anything has vectors.
until_ok "every file embedded" 900 embedded
until_ok "each note ranks first for its own paraphrase" 150 found_vec

# MCP, as Claude Code and opencode call it: stateless Streamable HTTP.
init=$(mcp initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"e2e","version":"1"}}')
[ -n "$(jq -r '.serverInfo.name // empty' <<<"$init")" ] || fail "MCP initialize returned no serverInfo: $init"
tools=$(mcp tools/list '{}' | jq -r '.tools[].name' | sort | tr '\n' ' ')
for t in query get; do [[ " $tools" == *" $t "* ]] || fail "MCP tools/list has no '$t' (got: $tools)"; done
say "ok    MCP initialize and tools/list ($tools)"
got=$(mcp tools/call "{\"name\":\"get\",\"arguments\":{\"file\":\"qmd://workspace/${NOTE}\"}}" | jq -r '.content[0].resource.text // .content[0].text // empty')
grep -q "$TOKEN" <<<"$got" || fail "MCP get did not return the note: ${got:0:200}"
say "ok    MCP get returned the note"

out=$(QMD_URL="$QMD" "${DECREE_LIB:-/work/.decree/lib}/recall/search.sh" "$TOKEN" 2>&1) || fail "search command failed: $out"
grep -q "$NOTE" <<<"$out" || fail "search command did not print $NOTE: ${out:0:300}"
say "ok    the search command prints $NOTE"
