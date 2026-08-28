#!/usr/bin/env bash
# test-model-tiers.sh — the VRAM tier table.
#
# The table is the single place that decides which models a user ends up
# running, and it is consumed by two callers that write straight into
# .env.shared (src/quest.sh on first run, src/lib/models.sh later). A silent
# typo here — a tag that does not exist, a tier that emits no EXIST_MODEL_CHAT,
# an embedding dimension that stops matching its model — surfaces much later as
# ollama 404s or a corrupt vector index. So assert the shape, not the taste.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TIERS="${REPO_DIR}/src/utils/model-tiers.sh"

[[ -f "$TIERS" ]] || TIERS="/repo/src/utils/model-tiers.sh"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

# shellcheck source=/dev/null
. "$TIERS"

# ── The table itself ──────────────────────────────────────────────────────────

[[ "${#MODEL_TIERS[@]}" -ge 2 ]] \
    && _ok "table has tiers" \
    || _fail "table has tiers" "found ${#MODEL_TIERS[@]}"

# Every row must have all six tab-separated fields, or `read` silently leaves
# later variables empty and a tier emits a blank model name.
_bad_shape=""
for _row in "${MODEL_TIERS[@]}"; do
    IFS=$'\t' read -r _gb _label _chat _ctx _size _note <<< "$_row"
    [[ -n "$_gb" && -n "$_label" && -n "$_chat" && -n "$_ctx" && -n "$_size" && -n "$_note" ]] \
        || _bad_shape+="${_gb:-?} "
    [[ "$_gb"  =~ ^[0-9]+$ ]] || _bad_shape+="${_gb:-?}(gb) "
    [[ "$_ctx" =~ ^[0-9]+$ ]] || _bad_shape+="${_gb:-?}(ctx) "
    # A tag with no colon is a family name, which resolves to :latest and drifts.
    [[ "$_chat" == *:* ]]     || _bad_shape+="${_gb:-?}(untagged) "
done
[[ -z "$_bad_shape" ]] \
    && _ok "every tier row is complete and well-typed" \
    || _fail "every tier row is complete and well-typed" "problems in: $_bad_shape"

# Tiers must be unique and ascending — the picker positions the cursor by
# matching on gb, and a duplicate would make the choice ambiguous.
_gbs=(); for _row in "${MODEL_TIERS[@]}"; do _gbs+=("${_row%%	*}"); done
[[ "$(printf '%s\n' "${_gbs[@]}" | sort -n | uniq | wc -l)" -eq "${#_gbs[@]}" ]] \
    && _ok "tier sizes are unique" \
    || _fail "tier sizes are unique" "duplicates in: ${_gbs[*]}"

[[ "$(printf '%s\n' "${_gbs[@]}")" == "$(printf '%s\n' "${_gbs[@]}" | sort -n)" ]] \
    && _ok "tiers are listed smallest first" \
    || _fail "tiers are listed smallest first" "order: ${_gbs[*]}"

# ── The default ───────────────────────────────────────────────────────────────

model_tier_row "$MODEL_TIER_DEFAULT_GB" >/dev/null 2>&1 \
    && _ok "MODEL_TIER_DEFAULT_GB names a real tier" \
    || _fail "MODEL_TIER_DEFAULT_GB names a real tier" "no tier for '${MODEL_TIER_DEFAULT_GB}'"

# .env.exist.shared ships the default tier's values. If they drift apart, a
# non-interactive install silently gets different models than the picker's
# default hands out.
_shipped="${REPO_DIR}/.env.exist.shared"
[[ -f "$_shipped" ]] || _shipped="/repo/.env.exist.shared"
if [[ -f "$_shipped" ]]; then
    _drift=""
    while IFS='=' read -r _k _v; do
        [[ -n "$_k" ]] || continue
        # EXIST_VRAM_GB is the record of HAVING BEEN ASKED, not a model value, so
        # it ships blank on purpose — quest's picker fires only while it is empty.
        # Asserting it against the default tier is what pinned it at 8 and made
        # the question unreachable. The six model keys still have to agree.
        [[ "$_k" == "EXIST_VRAM_GB" ]] && continue
        _shipped_v="$(grep -m1 "^${_k}=" "$_shipped" | cut -d= -f2-)"
        [[ "$_shipped_v" == "$_v" ]] || _drift+="${_k} (ships '${_shipped_v}', tier says '${_v}') "
    done < <(model_tier_env "$MODEL_TIER_DEFAULT_GB")

    # ...and the blankness itself is load-bearing, so assert it directly.
    [[ -z "$(grep -m1 '^EXIST_VRAM_GB=' "$_shipped" | cut -d= -f2-)" ]] \
        && _ok "EXIST_VRAM_GB ships blank (so quest asks on first run)" \
        || _fail "EXIST_VRAM_GB ships blank (so quest asks on first run)" \
                 "ships '$(grep -m1 '^EXIST_VRAM_GB=' "$_shipped" | cut -d= -f2-)'"

    [[ -z "$_drift" ]] \
        && _ok ".env.exist.shared matches the default tier" \
        || _fail ".env.exist.shared matches the default tier" "$_drift"
else
    _fail ".env.exist.shared matches the default tier" "could not find .env.exist.shared"
fi

# ── model_tier_env ────────────────────────────────────────────────────────────

# Every tier must emit every key a consumer reads, or a swap leaves a stale
# value behind from the previous tier.
_required=(EXIST_VRAM_GB EXIST_MODEL_CHAT EXIST_MODEL_CHAT_NUM_CTX
           EXIST_MODEL_EXTRACT EXIST_MODEL_VISION EXIST_MODEL_EMBED EXIST_MODEL_EMBED_DIM)
_missing=""
for _gb in "${_gbs[@]}"; do
    _out="$(model_tier_env "$_gb")"
    for _key in "${_required[@]}"; do
        grep -qE "^${_key}=.+" <<< "$_out" || _missing+="${_gb}:${_key} "
    done
done
[[ -z "$_missing" ]] \
    && _ok "every tier emits every required key, non-empty" \
    || _fail "every tier emits every required key, non-empty" "$_missing"

# bge-m3 is 1024-dimensional. A mismatch here corrupts openviking's index in a
# way that only shows up as bad search results, so pin it explicitly.
_dim="$(model_tier_env "$MODEL_TIER_DEFAULT_GB" | grep '^EXIST_MODEL_EMBED_DIM=' | cut -d= -f2-)"
_emb="$(model_tier_env "$MODEL_TIER_DEFAULT_GB" | grep '^EXIST_MODEL_EMBED=' | cut -d= -f2-)"
{ [[ "$_emb" == "bge-m3" && "$_dim" == "1024" ]]; } \
    && _ok "embedding model and dimension agree" \
    || _fail "embedding model and dimension agree" "${_emb} / ${_dim}"

# The embedding model must be identical across tiers — changing it on a tier
# swap would silently invalidate an existing vector index.
_embeds="$(for _gb in "${_gbs[@]}"; do model_tier_env "$_gb" | grep '^EXIST_MODEL_EMBED='; done | sort -u | wc -l)"
[[ "$_embeds" -eq 1 ]] \
    && _ok "embedding model is the same for every tier" \
    || _fail "embedding model is the same for every tier" "found ${_embeds} distinct values"

# An unknown tier must fail loudly rather than emit a half-filled env.
model_tier_env 999 >/dev/null 2>&1 \
    && _fail "unknown tier is rejected" "returned 0 for a tier that does not exist" \
    || _ok "unknown tier is rejected"

# ── The CPU-only tier ─────────────────────────────────────────────────────────

# gb=0 is load-bearing beyond the model choice: generate-compose.ts keys the
# GPU-reservation strip off EXIST_VRAM_GB being exactly "0". Renaming or
# renumbering that tier silently breaks CPU-only installs, where the symptom is
# `docker compose up` failing on a device driver rather than anything about models.
model_tier_row 0 >/dev/null 2>&1 \
    && _ok "a CPU-only (0) tier exists" \
    || _fail "a CPU-only (0) tier exists" "generate-compose.ts strips GPU reservations on exactly this value"

_cpu_gb="$(model_tier_env 0 | grep "^EXIST_VRAM_GB=" | cut -d= -f2-)"
[[ "$_cpu_gb" == "0" ]] \
    && _ok "the CPU tier emits EXIST_VRAM_GB=0 verbatim" \
    || _fail "the CPU tier emits EXIST_VRAM_GB=0 verbatim" "got '${_cpu_gb}' — generate-compose.ts compares this against the string 0"

# EXIST_VRAM_GB=0 is no longer the primary signal — EXIST_GPU_VENDOR is — but it
# remains the fallback for every .env.shared written before the vendor question
# existed. If generate-compose.ts stops reading it, those installs silently
# start getting nvidia reservations they cannot satisfy.
GC="${REPO_DIR}/src/generate-compose.ts"
[[ -f "$GC" ]] || GC="/src/generate-compose.ts"
if grep -q "EXIST_VRAM_GB" "$GC" 2>/dev/null && grep -q "EXIST_GPU_VENDOR" "$GC" 2>/dev/null; then
    _ok "generate-compose.ts reads both EXIST_GPU_VENDOR and the EXIST_VRAM_GB fallback"
else
    _fail "generate-compose.ts reads both EXIST_GPU_VENDOR and the EXIST_VRAM_GB fallback" \
          "the legacy VRAM=0 fallback is how pre-vendor installs still get their reservations stripped"
fi

# ── --gpu-only ────────────────────────────────────────────────────────────────
# The vendor question is asked first, so by the time the VRAM picker runs we
# already know there is a card. Offering "None (CPU)" there would let someone
# answer "nvidia" and then "no GPU", producing a machine with a stripped
# reservation and a GPU sitting idle.
_all_n="$(model_tier_lines | wc -l)"
_gpu_n="$(model_tier_lines --gpu-only | wc -l)"
[[ "$_gpu_n" -eq $(( _all_n - 1 )) ]] \
    && _ok "--gpu-only drops exactly one tier" \
    || _fail "--gpu-only drops exactly one tier" "all=${_all_n} gpu-only=${_gpu_n}"

[[ "$(model_tier_lines --gpu-only | grep -c '^0	')" -eq 0 ]] \
    && _ok "--gpu-only drops the CPU tier specifically" \
    || _fail "--gpu-only drops the CPU tier specifically" "gb=0 is still offered"

[[ "$(model_tier_lines | grep -c '^0	')" -eq 1 ]] \
    && _ok "the CPU tier is still reachable without --gpu-only" \
    || _fail "the CPU tier is still reachable without --gpu-only" "run models could no longer select CPU"


# The CPU tier should not hand someone a model that needs a card to be usable.
_cpu_chat="$(model_tier_env 0 | grep "^EXIST_MODEL_CHAT=" | cut -d= -f2-)"
_cpu_ctx="$(model_tier_env 0 | grep "^EXIST_MODEL_CHAT_NUM_CTX=" | cut -d= -f2-)"
[[ -n "$_cpu_chat" && "$_cpu_ctx" -le 16384 ]] \
    && _ok "the CPU tier keeps context modest" \
    || _fail "the CPU tier keeps context modest" "ctx ${_cpu_ctx} will be painful without a GPU"

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
