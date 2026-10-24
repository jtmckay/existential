#!/usr/bin/env bash
# exist.eval.sh — measure qmd's retrieval on a fixed fixture, in a throwaway
# container, and check that the index follows the files.
#
#   ./existential.sh run qmd eval            keyword-only vs neural-only vs hybrid
#   QMD_EVAL_RERANK=1 ./existential.sh run qmd eval    also hybrid + reranking (slow on CPU)
#
# The corpus is ai/qmd/eval/workspace (personal notes with a long runbook, code
# blocks, a conversation and the decision that followed it) plus this repo's own
# docs copied in as distractors. Secret-shaped, hidden and gitignored files are
# planted at run time, never tracked. Queries and expected sources:
# ai/qmd/eval/queries.tsv.
#
# Runs on the host (it needs docker), touches nothing of the stack's: the
# workspace is a temp copy and the index a temp dir, both removed on exit. The
# downloaded model is kept in ~/.cache/existential/qmd-eval so a re-run doesn't
# fetch it again. Fails on a leaked exclusion, an index that doesn't follow an
# edit, rename, delete or new ignore rule, or hybrid finding fewer expected
# sources than keyword search alone.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
REFRESH=5
IMAGE=existential/qmd:eval
NAME="qmd-eval-$$"
MODELS="${XDG_CACHE_HOME:-$HOME/.cache}/existential/qmd-eval/models"
TMP="$(mktemp -d)"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

FAIL=0
bad() { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }
good() { echo "  ok    $*"; }

# ── corpus ───────────────────────────────────────────────────────────────────
W="$TMP/workspace"
cp -r "$HERE/eval/workspace" "$W"
mkdir -p "$W/docs" "$W/reference" "$W/migrations" "$W/private" "$W/.decree/runs" "$TMP/cache/qmd" "$MODELS"
cp -r "$REPO/site/docs/." "$W/docs/"
cp "$REPO"/.claude/reference/*.md "$REPO/CLAUDE.md" "$W/reference/"
cp "$REPO"/.decree/migrations/*.md "$W/migrations/"
# What must never be found: a gitignored folder, a hidden one, a dotfile.
echo "# Bank: PIN zebracobalt" > "$W/private/bank.md"
echo "# Run log zebracobalt" > "$W/.decree/runs/log.md"
echo "TOKEN=zebracobalt" > "$W/.env"
ln -s "$MODELS" "$TMP/cache/qmd/models"
chmod -R a+rX "$TMP"

# ── start ────────────────────────────────────────────────────────────────────
echo "Building $IMAGE..."
docker build -q -t "$IMAGE" "$HERE" >/dev/null
started=$(date +%s)
docker run -d --name "$NAME" --init --user "$(id -u):$(id -g)" -e QMD_REFRESH_SECONDS=$REFRESH \
    -v "$W:/workspace:ro" -v "$TMP/cache:/cache" -v "$MODELS:$MODELS" "$IMAGE" >/dev/null
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")
until grep -q . "$TMP/cache/refresh.status" 2>/dev/null; do
    sleep 2
    (( $(date +%s) - started < 900 )) || { echo "no index after 15 minutes"; docker logs "$NAME" | tail -20; exit 1; }
done
ready=$(( $(date +%s) - started ))
docs=$(find "$W" -name '*.md' -not -path '*/.*' | wc -l)
echo "First index: $(cat "$TMP/cache/refresh.status") after ${ready}s (${docs} Markdown files, model download included on a first run)"
[[ "$(cat "$TMP/cache/refresh.status")" == ok* ]] || bad "neural index not ready: $(cat "$TMP/cache/refresh.status")"

query() {  # <json searches> <rerank true|false> → result paths, one per line
    curl -s --max-time 120 "http://$IP:8181/query" -H 'Content-Type: application/json' \
        -d "{\"searches\": $1, \"limit\": 5, \"rerank\": $2}" | jq -r '.results[].file' | sed -E 's#^qmd://[^/]+/##'
}

# ── retrieval ────────────────────────────────────────────────────────────────
declare -A RECALL
arm() {  # <name> <lex|vec|hybrid> <rerank>
    local name=$1 mode=$2 rerank=$3 n=0 h1=0 h5=0 ms=0 kind lex vec want s paths top t0 ok1 ok5 g w hit
    while IFS=$'\t' read -r kind lex vec want; do
        [[ -z "$kind" || "$kind" == \#* ]] && continue
        case $mode in
            lex)    s=$(jq -nc --arg l "$lex" '[{type:"lex",query:$l}]') ;;
            vec)    s=$(jq -nc --arg v "$vec" '[{type:"vec",query:$v}]') ;;
            hybrid) s=$(jq -nc --arg l "$lex" --arg v "$vec" '[{type:"lex",query:$l},{type:"vec",query:$v}]') ;;
        esac
        t0=$(date +%s%N); paths=$(query "$s" "$rerank" | awk '!seen[$0]++'); ms=$(( ms + ($(date +%s%N) - t0) / 1000000 ))
        top=$(head -1 <<<"$paths"); ok1=0; ok5=1
        for g in $want; do
            hit=0
            for w in ${g//|/ }; do grep -qxF "$w" <<<"$paths" && hit=1; [[ "$top" == "$w" ]] && ok1=1; done
            (( hit )) || ok5=0
        done
        n=$((n + 1)); h1=$((h1 + ok1)); h5=$((h5 + ok5))
        (( ok5 )) || [[ -z "${VERBOSE:-}" ]] || echo "        $name missed: $vec"
    done < "$HERE/eval/queries.tsv"
    RECALL[$name]=$h5
    printf '  %-16s best first %2d/%d   every expected source in top 5 %2d/%d   %5d ms/query\n' \
        "$name" "$h1" "$n" "$h5" "$n" "$(( ms / n ))"
}
echo; echo "Retrieval (queries.tsv):"
arm keyword-only lex false
arm neural-only vec false
arm hybrid hybrid false
[[ -n "${QMD_EVAL_RERANK:-}" ]] && arm hybrid+rerank hybrid true
(( RECALL[hybrid] >= RECALL[keyword-only] )) || bad "hybrid found fewer expected sources than keyword-only"

# ── exclusions ───────────────────────────────────────────────────────────────
echo; echo "Exclusions:"
leaked=$(query '[{"type":"lex","query":"zebracobalt"}]' false)
[[ -z "$leaked" ]] && good "gitignored, hidden and dotfiles are not searchable" || bad "found: $leaked"

# ── freshness ────────────────────────────────────────────────────────────────
echo; echo "Freshness (refresh every ${REFRESH}s):"
lex_top() { query "$(jq -nc --arg l "$1" '[{type:"lex",query:$l}]')" false | head -1; }
export IP; export -f query lex_top
within() {  # <what> <seconds> <test command...>
    local what=$1 limit=$2 t0; shift 2; t0=$(date +%s)
    until "$@"; do sleep 1; (( $(date +%s) - t0 < limit )) || { bad "$what: not after ${limit}s"; return; }; done
    good "$what after $(( $(date +%s) - t0 ))s"
}
echo "Chain wax swapped for Squirt lube." >> "$W/notes/scratch-to-rename.md"
within "edit searchable" 60 bash -c "[[ \"\$(lex_top Squirt)\" == notes/scratch-to-rename.md ]]"
mv "$W/notes/scratch-to-rename.md" "$W/notes/bike.md"
within "rename followed" 60 bash -c "[[ \"\$(lex_top Squirt)\" == notes/bike.md ]]"
rm "$W/notes/to-delete.md"
within "delete gone" 60 bash -c "[[ -z \"\$(lex_top Corolla)\" ]]"
printf '# Climbing\n\nThursday sessions moved to the Boulder Barn.\n' > "$W/notes/climbing.md"
within "new note searchable" 60 bash -c "[[ \"\$(lex_top 'Boulder Barn')\" == notes/climbing.md ]]"
echo "notes/daily/" >> "$W/.gitignore"
within "newly gitignored folder dropped" 60 bash -c "[[ -z \"\$(lex_top dentist)\" ]]"
MEM=$(docker stats --no-stream --format '{{.MemUsage}}' "$NAME" | cut -d/ -f1)
docker restart "$NAME" >/dev/null
# A restart can hand the container a new address on the default bridge.
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME"); export IP
printf '# Kayak\n\nPermit KX4471 renewed.\n' > "$W/notes/kayak.md"
within "restart keeps the index, catches up" 90 bash -c "[[ \"\$(lex_top KX4471)\" == notes/kayak.md ]]"

# ── cost ─────────────────────────────────────────────────────────────────────
echo; echo "Cost:"
echo "  memory          ${MEM} (after the queries above, model loaded)"
echo "  index on disk   $(du -sh "$TMP/cache/qmd/index.sqlite" | cut -f1)"
echo "  models on disk  $(du -shL "$MODELS" | cut -f1)"
echo "  image           $(docker image ls "$IMAGE" --format '{{.Size}}')"

echo
(( FAIL == 0 )) && echo "qmd eval: ok" || { echo "qmd eval: ${FAIL} failure(s)"; exit 1; }
