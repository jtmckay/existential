#!/usr/bin/env bash
# search — search the workspace from a terminal, without MCP: the same hybrid
# (keyword + neural) query the AI tools send qmd, over its REST endpoint.
#
#   search <the words you remember>
#
# Keywords find what hybrid search finds; a whole question works too, but every
# word of it must match for the keyword half to help, so it finds less
# (site/docs/ai/qmd.md has the numbers).
#
# Prints the best passage of each of the 10 best hits, best first, each as path:line (relative to the
# workspace) and the lines around the hit. A PDF or Word file is shown as the
# file itself, since its line numbers count lines of the extracted text, and a
# PDF hit as its page (the last "## Page N" heading above the hit).
#
# Run by path (hence 755): code-server links it onto PATH as `search` when
# the Search add-on is on; on the host, `./existential.sh run qmd search`.
set -euo pipefail

url="${QMD_URL:-http://qmd:8181}"
(( $# )) || { echo "usage: search <the words you remember>" >&2; exit 2; }

body=$(jq -nc --arg q "$*" '{searches: [{type: "lex", query: $q}, {type: "vec", query: $q}], limit: 10, rerank: false}')
res=$(curl -fsS --max-time 60 "$url/query" -H 'Content-Type: application/json' -d "$body" 2>&1) ||
    { echo "search: qmd did not answer at $url/query: $res" >&2; exit 1; }

# Files with no vectors yet are found by keyword only: say so, never hide it.
pending=$(curl -sS --max-time 10 "$url/mcp" -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"status","arguments":{}}}' 2>/dev/null |
    sed -n 's/^data: //p' | jq -r '.result.structuredContent.needsEmbedding // 0' 2>/dev/null || echo 0)
[[ "${pending:-0}" == 0 ]] ||
    echo "search: ${pending} file(s) have no neural index yet, so they match by exact words only (docker logs qmd)." >&2

# The page of a PDF hit: the last "## Page N" heading at or above <line>, read
# with the MCP get tool, since the extracted text lives only in qmd_cache.
page() {  # <qmd://documents/... file> <line>
    curl -sS --max-time 10 "$url/mcp" -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -d "$(jq -nc --arg f "$1" --argjson n "$2" '{jsonrpc: "2.0", id: 1, method: "tools/call",
              params: {name: "get", arguments: {file: $f, fromLine: 1, maxLines: $n, lineNumbers: false}}}')" 2>/dev/null |
        sed -n 's/^data: //p' | jq -r '.result.content[0].resource.text // empty' 2>/dev/null |
        sed -n 's/^## Page \([0-9]*\)$/\1/p' | tail -1
}

if [[ "$(jq '.results | length' <<<"$res")" == 0 ]]; then
    echo "Nothing found. That doesn't mean it isn't there: try other words." >&2
    exit 1
fi

# qmd's snippet starts with a "@@ -<start>,<n> @@" header, and its own line labels
# are off by it: number the lines from <start> instead.
jq -c 'def lines: split("\n") as $l
         | (($l[0] | capture("^[0-9]+: @@ -(?<s>[0-9]+)") | .s | tonumber) // null) as $s
         | if $s == null then . else
             [$l[1:] | to_entries[] | "\($s + .key): \(.value | sub("^[0-9]+: "; ""))"] | join("\n") end;
       # One hit per file, its best; qmd can return several chunks of one file.
       reduce .results[] as $r ([]; if any(.[]; .file == $r.file) then . else . + [$r] end)
       | .[] | [.file, (.line | tostring), .title, (.snippet | lines)]' <<<"$res" |
while IFS= read -r r; do
    file=$(jq -r '.[0]' <<<"$r"); line=$(jq -r '.[1]' <<<"$r"); title=$(jq -r '.[2]' <<<"$r")
    uri=$file; file="${file#qmd://}"; coll="${file%%/*}"; file="${file#*/}"
    file=$(printf '%b' "${file//%/\\x}")   # qmd URL-encodes each path segment
    if [[ "$coll" == documents ]]; then
        where="${file%.md}"
        if [[ "${where,,}" == *.pdf ]]; then p=$(page "$uri" "$line" || true); where+="${p:+ page $p}"; fi
    else
        where="$file:$line"
    fi
    printf '\n%s  %s\n' "$where" "$title"
    jq -r '.[3]' <<<"$r" | sed 's/^/    /'
done
