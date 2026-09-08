#!/usr/bin/env bash
# test-comfy-workflows.sh — the comfy routine's workflow bindings still address
# real nodes.
#
# automation/lib/comfy/workflows/<type>.yml is the whole interface between a
# message and a ComfyUI graph: it names, per parameter, the node id and input to
# write. The graphs are captured out of ComfyUI, and re-capturing one renumbers
# every node — so a binding can go stale without anything failing loudly. The
# result is worse than an error: ComfyUI happily runs the untouched template and
# hands back an image of somebody else's prompt.
#
# patch.ts refuses to submit a stale binding at runtime. This is the same check
# run offline, so a re-capture is caught at commit time rather than by a routine
# that only runs when someone queues a message.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
[[ -f "${SRC_DIR}/quest.sh" ]] || SRC_DIR="/src"

REPO_DIR="$(cd "${SRC_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"

WORKFLOWS="${REPO_DIR}/automation/lib/comfy/workflows"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

if ! command -v yq >/dev/null 2>&1; then
    echo "  skipped — yq not available"
    exit 0
fi

# Every bind in a binding resolves. `input:` must name an input the node already
# has (a rename is as silent as a renumber); `widget:` must name a node in the
# embedded UI graph, but only for the captures that carry one — an "Export (API)"
# workflow is a bare prompt map with no UI graph, and its bindings declare no
# widgets.
check_binding() {
    local binding="$1" name workflow json
    name="$(basename "$binding" .yml)"

    workflow="$(yq -r '.workflow // ""' "$binding")"
    if [ -z "$workflow" ]; then
        _fail "$name" 'no "workflow:" key'
        return
    fi

    json="${WORKFLOWS}/${workflow}"
    if [ ! -f "$json" ]; then
        _fail "$name" "names a missing workflow: $workflow"
        return
    fi

    local problems
    problems=$(jq -rn \
        --slurpfile wf "$json" \
        --argjson binding "$(yq -o=json '.' "$binding")" '
        ($wf[0].prompt // $wf[0])                              as $prompt |
        ($wf[0].extra_data.extra_pnginfo.workflow.nodes // null) as $ui     |
        (
          [ ($binding.params // {}) | to_entries[] | .key as $p
            | ((.value.bind // []) + (.value.mode_bind // []))[]
            | { label: $p, node: (.node | tostring), input: (.input // null), widget: (.widget // null) } ]
          +
          [ ($binding.items.branches // []) | to_entries[] | ("item " + ((.key + 1) | tostring)) as $i
            | .value | to_entries[]
            | { label: ($i + " " + .key), node: (.value.node | tostring),
                input: (.value.input // null), widget: (.value.widget // null) } ]
        ) as $binds |
        [ $binds[]
          | . as $b
          | ( if $b.input != null then
                if $prompt[$b.node] == null then
                  "\($b.label): node \($b.node) is not in the workflow"
                elif ($prompt[$b.node].inputs | has($b.input)) | not then
                  "\($b.label): node \($b.node) (\($prompt[$b.node].class_type)) has no input \"\($b.input)\""
                else empty end
              else empty end ),
            ( if $b.widget != null and $ui != null then
                if [ $ui[] | select((.id | tostring) == $b.node) ] | length == 0 then
                  "\($b.label): node \($b.node) is not in the embedded UI graph"
                else empty end
              else empty end )
        ] | join("; ")')

    if [ -n "$problems" ]; then
        _fail "$name" "$problems"
        return
    fi

    # A batch binding whose max outruns its branch list would let patch.ts accept
    # more items than there are places to put them.
    local max branches
    max="$(yq -r '.items.max // ""' "$binding")"
    branches="$(yq -r '.items.branches // [] | length' "$binding")"
    if [ -n "$max" ] && [ "$max" -gt "$branches" ]; then
        _fail "$name" "items.max is $max but there are only $branches branches"
        return
    fi

    _ok "$name"
}

for binding in "$WORKFLOWS"/*.yml; do
    check_binding "$binding"
done

# A workflow JSON nobody binds is dead weight — the routine can only reach a
# graph through a binding, so an unreferenced capture is either an unfinished
# flow or one whose binding got renamed.
orphans=""
for json in "$WORKFLOWS"/*.json; do
    base="$(basename "$json")"
    grep -qF "$base" "$WORKFLOWS"/*.yml || orphans+=" $base"
done
if [ -n "$orphans" ]; then
    _fail "no orphan workflows" "no binding names:$orphans"
else
    _ok "no orphan workflows"
fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '  Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
