#!/usr/bin/env bash
# exist.test.sh — diagnose ollama: reachability, configured model, num_ctx,
# memory headroom, and a quick generation benchmark.
#
# Read-only. /api/generate is a single prompt with num_predict=5, no state
# carried over.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "ollama" EXIST_IS_AI_OLLAMA
skip_if_disabled

# ── Config ────────────────────────────────────────────────────────────────────

# Model choice is global, never per-service: EXIST_MODEL_CHAT is written by the
# VRAM tier table (src/utils/model-tiers.sh) via quest / `run models`. Hardcoding
# a tag here made this test demand gemma4:26b on every machine — a tag that is
# not even in the tier table — so a correctly configured CPU-tier host failed.
load_env_exist
MODEL="${OLLAMA_MODEL:-${EXIST_MODEL_CHAT:-}}"

# Address is per-role and resolved in one place. Hardcoding http://ollama:11434
# here tested a container that does not exist on an install pointed at another
# box (EXIST_OLLAMA_URL / EXIST_OLLAMA_URL_CHAT), and reported it as ollama being
# down. Never read the role keys directly — see src/utils/model-endpoints.sh.
# shellcheck source=../../src/utils/model-endpoints.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/utils" && pwd)/model-endpoints.sh"
OLLAMA_URL="${OLLAMA_URL:-$(endpoint_for chat)}"
if [ -z "$MODEL" ]; then
    fail "EXIST_MODEL_CHAT set" \
         "neither OLLAMA_MODEL nor EXIST_MODEL_CHAT is set" \
         "Run ./existential.sh run models to pick a VRAM tier"
    finish
fi

# The context the configured tier asks for. Falls back to the tier-0 value so a
# missing key degrades to a floor rather than to 0 (which would read as "unset").
EXPECT_CTX="${EXIST_MODEL_CHAT_NUM_CTX:-8192}"

# Hermes requires 64,000 tokens of context, and it enforces that itself: below
# the floor it raises "context window ... below the minimum 64,000 required by
# Hermes Agent" and refuses to start the agent. Every tier in the table ships
# 65536, so no stock configuration falls short — this branch fires only on a
# hand-edited EXIST_MODEL_CHAT_NUM_CTX, or on a model built before the floor
# existed and never rebuilt.
HERMES_CTX_WANT=65536

# ── 1. Reachability ───────────────────────────────────────────────────────────

TAGS=$(curl -sS --max-time 5 "${OLLAMA_URL}/api/tags" 2>/dev/null || true)
if [ -z "$TAGS" ]; then
    fail "ollama reachable at ${OLLAMA_URL}" \
         "no response within 5s" \
         "docker ps | grep ollama; docker logs ollama"
    finish
fi
ok "ollama reachable at ${OLLAMA_URL}"

# Routing coverage — same /api/tags reached via caddy. Separates "ollama
# down" from "caddy/pihole routing broken".
probe_caddy "ollama /api/tags" ollama /api/tags 200

# ── 2. Model presence ────────────────────────────────────────────────────────

# jq, not python3: CLAUDE.md rules Python out for code we own, and every other
# probe in this repo already reads JSON with jq.
NAMES=$(echo "$TAGS" | jq -r '.models[]?.name // empty' 2>/dev/null || true)

if [ -z "$NAMES" ]; then
    # No models AT ALL is the pull step not having run yet, not a fault. Only the
    # Core quest copies the ollama migrations; the Local AI Lab quest deliberately
    # leaves pulling to the user (`./existential.sh run ollama pull-models`), so a
    # fresh install of it legitimately has an empty ollama. Failing here reported
    # a working stack as broken. Drift is still caught: one model present and the
    # configured one missing falls through to the fail below.
    skip "model '${MODEL}' present" \
         "no models pulled yet — ./existential.sh run ollama pull-models"
    finish
fi

# Exact tag, or any tag sharing the base name before the colon, so a pulled
# "llama3.2:3b" satisfies a configured "llama3.2" and vice versa.
if printf '%s\n' "$NAMES" | awk -F: -v base="${MODEL%%:*}" -v full="$MODEL" \
        '$0 == full || $1 == base { found = 1 } END { exit !found }'; then
    ok "model '${MODEL}' present"
else
    fail "model '${MODEL}' present" \
         "available: $(printf '%s\n' "$NAMES" | paste -sd, - | sed 's/,/, /g')" \
         "ollama pull ${MODEL}   (or update OLLAMA_MODEL)"
    finish
fi

# ── 3. num_ctx ────────────────────────────────────────────────────────────────

MODEL_INFO=$(curl -sS "${OLLAMA_URL}/api/show" -d "{\"name\":\"${MODEL}\"}" 2>/dev/null || true)

# What the model is CURRENTLY SERVING, which is not the same as what its
# Modelfile bakes. A tag with no baked num_ctx inherits ollama's own default,
# which since 0.32 is *sized from VRAM* (`ollama serve --help`: "4k/32k/256k
# based on VRAM") rather than a fixed 4096 — so it is not merely small, it is
# unpredictable across machines. Invisible in /api/show either way, and the
# exact state that truncates hermes without reporting anything. /api/ps is the
# only place that shows it, so it wins when the model is loaded; /api/show is
# the cold fallback.
PS_JSON=$(curl -sS --max-time 5 "${OLLAMA_URL}/api/ps" 2>/dev/null || true)
read -r LOADED_CTX LOADED_SIZE LOADED_VRAM <<EOF
$(echo "$PS_JSON" | jq -r --arg want "$MODEL" '
    first(.models[]? | select(.model == $want or .name == $want)
          | "\(.context_length // 0) \(.size // 0) \(.size_vram // 0)")
    // "0 0 0"' 2>/dev/null || echo "0 0 0")
EOF
LOADED_CTX="${LOADED_CTX:-0}"; LOADED_SIZE="${LOADED_SIZE:-0}"; LOADED_VRAM="${LOADED_VRAM:-0}"

# Residency: how big the loaded instance actually is, and where it sits. This is
# the number to look at when deciding whether a context change will fit — it is
# what `ollama ps` shows, surfaced here so it does not need a docker exec.
if [ "$LOADED_SIZE" -gt 0 ]; then
    SIZE_MB=$(( LOADED_SIZE / 1024 / 1024 ))
    if [ "$LOADED_VRAM" -eq 0 ]; then
        WHERE="100% CPU (system RAM)"
    elif [ "$LOADED_VRAM" -ge "$LOADED_SIZE" ]; then
        WHERE="100% GPU"
    else
        WHERE="$(( LOADED_VRAM * 100 / LOADED_SIZE ))% GPU, rest spilled to system RAM"
    fi
    ok "resident: ${MODEL} ${SIZE_MB}MB, ${WHERE}, serving ctx ${LOADED_CTX}"
else
    ok "resident: ${MODEL} not currently loaded (ollama loads on first request)"
fi

# jq reads the JSON; awk reads .parameters, which is a plain "key value" block
# rather than JSON, so parsing it as text is what it actually is.
BAKED_CTX=$(echo "$MODEL_INFO" | jq -r '.parameters // ""' 2>/dev/null \
    | awk '$1 == "num_ctx" { print $2; found = 1; exit } END { if (!found) print 0 }')
BAKED_CTX="${BAKED_CTX:-0}"

# Prefer what is actually being served; fall back to the baked value when cold.
if [ "$LOADED_CTX" -gt 0 ]; then
    NUM_CTX="$LOADED_CTX"; CTX_SRC="serving"
else
    NUM_CTX="$BAKED_CTX"; CTX_SRC="Modelfile"
fi

# A loaded instance below its own baked value means ollama is running an
# instance created before the rebuild — it needs evicting, not re-creating.
if [ "$LOADED_CTX" -gt 0 ] && [ "$BAKED_CTX" -gt 0 ] && [ "$LOADED_CTX" -lt "$BAKED_CTX" ]; then
    warn "serving context matches the Modelfile" \
         "serving ${LOADED_CTX} but the tag is built for ${BAKED_CTX} — a stale instance is still resident" \
         "./existential.sh run ollama unload   (drops it; the next request reloads at ${BAKED_CTX})"
fi

if [ "$NUM_CTX" -eq 0 ]; then
    fail "num_ctx readable for ${MODEL}" \
         "no num_ctx baked into the tag, and it is not loaded — ollama will serve its own VRAM-sized default, which may be far below the tier" \
         "./existential.sh run ollama pull-models   (bakes num_ctx=${EXPECT_CTX})"
elif [ "$NUM_CTX" -lt "$EXPECT_CTX" ]; then
    fail "num_ctx >= ${EXPECT_CTX} (tier)" \
         "num_ctx=${NUM_CTX} but the configured tier asks for ${EXPECT_CTX}" \
         "The Modelfile did not apply. Re-run ./existential.sh run ollama"
elif [ "$NUM_CTX" -lt "$HERMES_CTX_WANT" ]; then
    fail "num_ctx >= ${HERMES_CTX_WANT} (hermes)" \
         "num_ctx=${NUM_CTX} matches the tier, but hermes refuses to start an agent below ${HERMES_CTX_WANT}" \
         "EXIST_MODEL_CHAT_NUM_CTX was hand-lowered, or this model predates the 64k floor. Set it back to ${HERMES_CTX_WANT} and re-run ./existential.sh run ollama pull-models"
else
    ok "num_ctx=${NUM_CTX} from ${CTX_SRC} (tier ${EXPECT_CTX}, hermes floor ${HERMES_CTX_WANT})"
fi

# ── 4. Memory headroom ────────────────────────────────────────────────────────

AVAIL_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
if [ "$AVAIL_KB" -gt 0 ] && [ "$NUM_CTX" -gt 0 ]; then
    # Compute the KV cache from the model's OWN geometry rather than a magic
    # divisor. Every divisor guess here has been wrong: it depends on layer
    # count, KV-head count and whether the architecture uses sliding-window
    # attention, which vary by an order of magnitude across the tier table.
    #
    #   KV bytes = layers × kv_heads × (key_len + val_len) × num_ctx × bytes
    #
    # ollama reports these under architecture-prefixed keys ("qwen3vl.block_count"),
    # so match on the suffix. bytes is 2 for the default f16 cache.
    # This is an upper bound: sliding-window models (the gemma4 tiers) hold full
    # cache on only a fraction of layers, so their real cost is lower.
    KV_MB=$(echo "$MODEL_INFO" | jq -r --argjson ctx "$NUM_CTX" '
        (.model_info // {}) as $i
        | ( [ $i | to_entries[] | select(.key | endswith(".block_count"))
              | select(.value | type == "number") | .value ] | first // 0 ) as $layers
        | ( [ $i | to_entries[] | select(.key | endswith(".attention.head_count_kv"))
              | select(.value | type == "number") | .value ] | first // 0 ) as $kv
        | ( [ $i | to_entries[] | select(.key | endswith(".attention.key_length"))
              | select(.value | type == "number") | .value ] | first // 0 ) as $klen
        | ( [ $i | to_entries[] | select(.key | endswith(".attention.value_length"))
              | select(.value | type == "number") | .value ] | first // 0 ) as $vlen
        | if ($layers > 0 and $kv > 0 and $klen > 0 and $vlen > 0)
          then ($layers * $kv * ($klen + $vlen) * $ctx * 2 / 1048576 | floor)
          else 0 end' 2>/dev/null || echo 0)
    KV_MB="${KV_MB:-0}"

    # Sub-GB values must not render as "0GB" — at the small end this number is
    # the whole point of the check.
    fmt_mb() {
        if [ "$1" -ge 1024 ]; then
            printf '%d.%dGB' "$(( $1 / 1024 ))" "$(( ($1 % 1024) * 10 / 1024 ))"
        else
            printf '%dMB' "$1"
        fi
    }

    if [ "$KV_MB" -eq 0 ]; then
        ok "KV cache size not computable for ${MODEL} (unknown geometry) — skipping headroom check"
    else
        AVAIL_MB=$(( AVAIL_KB / 1024 ))
        if [ "$KV_MB" -gt "$AVAIL_MB" ]; then
            fail "RAM headroom for KV cache" \
                 "KV cache for num_ctx=${NUM_CTX} needs ~$(fmt_mb "$KV_MB") (upper bound) but only $(fmt_mb "$AVAIL_MB") is available — loading this will swap or OOM" \
                 "Lower EXIST_MODEL_CHAT_NUM_CTX, free RAM, or set OLLAMA_KV_CACHE_TYPE=q8_0 in ai/ollama/.env to halve it"
        else
            ok "KV cache ~$(fmt_mb "$KV_MB") for num_ctx=${NUM_CTX}, $(fmt_mb "$AVAIL_MB") available"
        fi
    fi
fi

# ── 5. Generation benchmark ──────────────────────────────────────────────────

BENCH=$(curl -sS --max-time 60 "${OLLAMA_URL}/api/generate" \
    -d "{\"model\":\"${MODEL}\",\"prompt\":\"Reply with only the word yes.\",\"options\":{\"num_predict\":5},\"stream\":false}" 2>/dev/null || true)

if [ -z "$BENCH" ]; then
    fail "generation benchmark" \
         "no response from /api/generate within 60s" \
         "docker logs ollama; ollama ps"
else
    RATE=$(echo "$BENCH" | jq -r '
        if (.eval_duration // 0) > 0 and (.eval_count // 0) > 0
        then (.eval_count / (.eval_duration / 1000000000) * 10 | round / 10 | tostring)
        else "unknown" end' 2>/dev/null || echo "unknown")
    ok "generation rate: ${RATE} tok/s"
fi

finish
