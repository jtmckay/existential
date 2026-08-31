#!/usr/bin/env bash
# test-gpu-vendor.sh — the GPU vendor question and everything keyed off it.
#
# EXIST_GPU_VENDOR decides what the generated compose file says about devices,
# and a wrong answer there does not degrade gracefully: docker refuses to create
# a container whose device driver it cannot satisfy, so one bad service takes
# `docker compose up` down for the whole stack. The failure surfaces as a docker
# error about capabilities, which points nowhere near this table.
#
# So the assertions here are about the contract between four files that have to
# agree — src/utils/gpu-vendor.sh, src/quest.sh, src/lib/models.sh and
# src/generate-compose.ts — plus the templates that carry x-exist-gpu blocks.
set -euo pipefail

# Two roots, because the adhoc container mounts them separately: src/ lands at
# /src and the repo at /repo, so a single "REPO_DIR/src" resolves to / in there
# and every path built from it silently misses. Same per-file fallback the other
# suites use — see test-compose.sh's GC.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
[[ -f "${SRC_DIR}/quest.sh" ]] || SRC_DIR="/src"

REPO_DIR="$(cd "${SRC_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"

VENDORS="${SRC_DIR}/utils/gpu-vendor.sh"
QUEST="${SRC_DIR}/quest.sh"
MODELS="${SRC_DIR}/lib/models.sh"
GC="${SRC_DIR}/generate-compose.ts"
SHIPPED="${REPO_DIR}/.env.exist.shared"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

# shellcheck source=/dev/null
. "$VENDORS"

# ── The table ─────────────────────────────────────────────────────────────────

_bad_shape=""
for _row in "${GPU_VENDORS[@]}"; do
    IFS=$'\t' read -r _slug _label _note <<< "$_row"
    [[ -n "$_slug" && -n "$_label" && -n "$_note" ]] || _bad_shape+="${_slug:-?} "
    # The slug is also a YAML key in x-exist-gpu and a value in .env.shared, so
    # anything needing quoting or case-folding there is a latent mismatch.
    [[ "$_slug" =~ ^[a-z]+$ ]] || _bad_shape+="${_slug:-?}(slug) "
done
[[ -z "$_bad_shape" ]] \
    && _ok "every vendor row is complete and well-typed" \
    || _fail "every vendor row is complete and well-typed" "problems in: $_bad_shape"

# nvidia and none are not optional: nvidia is the templates' own default, and
# none is the only answer that works on a machine with no card at all.
for _required in nvidia amd none; do
    gpu_vendor_is_valid "$_required" \
        && _ok "vendor '${_required}' exists" \
        || _fail "vendor '${_required}' exists" "GPU_VENDORS has no ${_required} row"
done

gpu_vendor_is_valid "definitely-not-a-gpu" \
    && _fail "an unknown vendor is rejected" "gpu_vendor_is_valid accepted a made-up slug" \
    || _ok "an unknown vendor is rejected"

gpu_vendor_is_valid "$GPU_VENDOR_DEFAULT" \
    && _ok "GPU_VENDOR_DEFAULT names a real vendor" \
    || _fail "GPU_VENDOR_DEFAULT names a real vendor" "no row for '${GPU_VENDOR_DEFAULT}'"

[[ "$(gpu_vendor_lines | wc -l)" -eq "${#GPU_VENDORS[@]}" ]] \
    && _ok "gpu_vendor_lines emits one line per vendor" \
    || _fail "gpu_vendor_lines emits one line per vendor" \
             "$(gpu_vendor_lines | wc -l) lines for ${#GPU_VENDORS[@]} vendors"

# ── What ships ────────────────────────────────────────────────────────────────

# Blank is the record of "not yet asked", exactly as for EXIST_VRAM_GB. Shipping
# a value here makes the question unreachable on first run — the bug that once
# pinned every machine at an 8 GB GPU.
if [[ -f "$SHIPPED" ]]; then
    grep -q '^EXIST_GPU_VENDOR=' "$SHIPPED" \
        && _ok "EXIST_GPU_VENDOR is declared in .env.exist.shared" \
        || _fail "EXIST_GPU_VENDOR is declared in .env.exist.shared" "key is missing entirely"

    [[ -z "$(grep -m1 '^EXIST_GPU_VENDOR=' "$SHIPPED" | cut -d= -f2-)" ]] \
        && _ok "EXIST_GPU_VENDOR ships blank (so quest asks on first run)" \
        || _fail "EXIST_GPU_VENDOR ships blank (so quest asks on first run)" \
                 "ships '$(grep -m1 '^EXIST_GPU_VENDOR=' "$SHIPPED" | cut -d= -f2-)'"
else
    _fail "EXIST_GPU_VENDOR ships blank" "could not find .env.exist.shared"
fi

# ── Order of the two questions ────────────────────────────────────────────────

# The whole point of this change: vendor gates the block, and "none" must not
# fall through to a VRAM picker. Asserting on source text is blunt, but the
# alternative is driving fzf, and the ordering is exactly what regressed before.
if [[ -f "$QUEST" ]]; then
    grep -q 'if \[\[ -z "$(env_get EXIST_GPU_VENDOR)" \]\]' "$QUEST" \
        && _ok "quest gates the hardware questions on EXIST_GPU_VENDOR" \
        || _fail "quest gates the hardware questions on EXIST_GPU_VENDOR" \
                 "gating on EXIST_VRAM_GB again would ask for VRAM before knowing there is a card"

    # The CPU tier must be applied without a picker on the "none" path.
    grep -q '_apply_tier 0' "$QUEST" \
        && _ok "quest pins the CPU tier when the answer is 'none'" \
        || _fail "quest pins the CPU tier when the answer is 'none'" \
                 "answering 'No GPU' must set EXIST_VRAM_GB=0 itself"

    grep -q 'model_tier_pick .* --gpu-only' "$QUEST" \
        && _ok "quest asks for VRAM with --gpu-only" \
        || _fail "quest asks for VRAM with --gpu-only" \
                 "the CPU tier would be offered to someone who just said they have a card"
else
    _fail "quest.sh is readable" "not found at ${QUEST}"
fi

if [[ -f "$MODELS" ]]; then
    grep -q 'gpu_vendor_pick' "$MODELS" \
        && _ok "run models re-asks the vendor question" \
        || _fail "run models re-asks the vendor question" \
                 "run models is the documented way to change a wrong first answer"

    grep -q 'env_set EXIST_GPU_VENDOR' "$MODELS" \
        && _ok "run models persists the vendor" \
        || _fail "run models persists the vendor" "the answer would be discarded"
else
    _fail "models.sh is readable" "not found at ${MODELS}"
fi

# ── Services a vendor forbids ────────────────────────────────────────────────
#
# `external` means the models live on another box. A local ollama under that
# answer serves nothing and its decree sidecar still pulls multi-GB models, so
# it must stay off. The rule regressed twice by being written out per call site,
# so these assert on the shared list and on every consumer honouring it.

vendor_disabled_services external | grep -qxF EXIST_IS_AI_OLLAMA \
    && _ok "external forbids EXIST_IS_AI_OLLAMA" \
    || _fail "external forbids EXIST_IS_AI_OLLAMA" \
             "external means the models are remote; a local ollama pulls GBs nothing queries"

for _v in nvidia amd none; do
    if [[ -z "$(vendor_disabled_services "$_v")" ]]; then
        _ok "${_v} forbids nothing"
    else
        _fail "${_v} forbids nothing" "only external names a remote ollama"
    fi
done

vendor_forbids_service external EXIST_IS_AI_OLLAMA \
    && _ok "vendor_forbids_service matches exactly" \
    || _fail "vendor_forbids_service matches exactly" "the predicate disagrees with the list"

if vendor_forbids_service external EXIST_IS_AI_OLLAMA_EXTRA 2>/dev/null; then
    _fail "vendor_forbids_service is not a prefix match" \
          "a substring match would disable services that merely share a prefix"
else
    _ok "vendor_forbids_service is not a prefix match"
fi

# Every consumer must go through the list. A hardcoded EXIST_IS_AI_OLLAMA=false
# is what let quest.sh, models.sh and e2e.sh drift apart in the first place.
E2E="${SRC_DIR}/test/e2e/e2e.sh"
for _f in "$QUEST" "$MODELS" "$E2E"; do
    _name="$(basename "$_f")"
    if [[ ! -f "$_f" ]]; then
        _fail "${_name} is readable" "not found at ${_f}"
        continue
    fi
    grep -q 'vendor_disabled_services\|vendor_forbids_service' "$_f" \
        && _ok "${_name} applies the vendor's forbidden-service list" \
        || _fail "${_name} applies the vendor's forbidden-service list" \
                 "it must not hardcode the rule — that is how this broke before"

    # Comments are stripped first: these files explain the rule they now apply
    # through the list, and prose about the old hardcoding is not the hardcoding.
    if sed 's/#.*//' "$_f" | grep -q 'EXIST_IS_AI_OLLAMA[= ]*false'; then
        _fail "${_name} has no hardcoded EXIST_IS_AI_OLLAMA=false" \
              "use vendor_disabled_services so all three stay in step"
    else
        _ok "${_name} has no hardcoded EXIST_IS_AI_OLLAMA=false"
    fi
done

# The enablement loop is where Core undid the vendor answer: quest asked first,
# then Core's services list turned ollama straight back on.
if [[ -f "$QUEST" ]]; then
    awk '/^_enable_quest_services\(\)/,/^}/' "$QUEST" | grep -q 'vendor_forbids_service' \
        && _ok "quest's service enablement respects the vendor" \
        || _fail "quest's service enablement respects the vendor" \
                 "a quest listing EXIST_IS_AI_OLLAMA would re-enable it under external"
fi

# ── The generator ─────────────────────────────────────────────────────────────

if [[ -f "$GC" ]]; then
    grep -q "x-exist-gpu" "$GC" \
        && _ok "generate-compose.ts applies the x-exist-gpu overlay" \
        || _fail "generate-compose.ts applies the x-exist-gpu overlay" \
                 "the per-service vendor blocks would be emitted verbatim into the compose file"

    # Every vendor the picker can return must be one the generator accepts, or a
    # user can pick something that then hard-exits the render.
    _unknown=""
    for _row in "${GPU_VENDORS[@]}"; do
        _slug="${_row%%	*}"
        grep -q "'${_slug}'" "$GC" || _unknown+="${_slug} "
    done
    [[ -z "$_unknown" ]] \
        && _ok "every pickable vendor is known to generate-compose.ts" \
        || _fail "every pickable vendor is known to generate-compose.ts" "missing: ${_unknown}"
else
    _fail "generate-compose.ts is readable" "not found at ${GC}"
fi

# ── The templates ─────────────────────────────────────────────────────────────

# A service that reserves an nvidia device and offers no AMD block is not
# necessarily wrong — but it is a claim that the service cannot use an AMD card,
# and that claim should be deliberate. Report it rather than assert it.
# The `if` rather than a trailing `&&` is load-bearing: a bare `[[ ]] &&` as the
# last statement of a loop body returns 1 when the test is false, and under
# `set -e` that ends the loop — truncating the list at the first template with
# no overlay, which is precisely the one this check exists to find.
_reserving=(); _with_amd=()
while IFS= read -r _tmpl; do
    grep -q 'driver: nvidia' "$_tmpl" || continue
    _reserving+=("$_tmpl")
    if grep -q 'x-exist-gpu' "$_tmpl"; then _with_amd+=("$_tmpl"); fi
done < <(find "${REPO_DIR}/ai" "${REPO_DIR}/services" "${REPO_DIR}/nas" "${REPO_DIR}/hosting" \
              -name 'docker-compose.exist.yml' 2>/dev/null | sort)

[[ "${#_reserving[@]}" -gt 0 ]] \
    && _ok "found ${#_reserving[@]} template(s) reserving an nvidia device" \
    || _fail "found templates reserving an nvidia device" "none — has the reservation moved?"

[[ "${#_with_amd[@]}" -eq "${#_reserving[@]}" ]] \
    && _ok "every nvidia-reserving template declares an x-exist-gpu block" \
    || _fail "every nvidia-reserving template declares an x-exist-gpu block" \
             "$(( ${#_reserving[@]} - ${#_with_amd[@]} )) template(s) reserve a GPU with no non-nvidia story"

# ── Self-check canary ─────────────────────────────────────────────────────────
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "${#FAIL_NAMES[@]}" -gt 0 ]]; then
    echo "Failed:"
    printf '  - %s\n' "${FAIL_NAMES[@]}"
fi

[[ "$FAIL" -eq 0 ]]
