#!/usr/bin/env bash
# ollama — decode-speed benchmark across increasing context sizes.
#
# Measures generation throughput (tok/s) as the prompt context grows. Decode
# speed drops as context fills because each step reads a larger KV cache; once
# the cache exceeds VRAM it spills to system RAM (~10x slower bandwidth), so the
# tok/s curve across runs is a quick read on where a model stops fitting.
#
# Runs a short-prompt baseline plus padded-context runs (~4k, ~8k, ~16k, ~28k
# tokens). Padding is repeated filler text generated in bash; each padded run
# asks for a fixed-length response so the generate tok/s is comparable.
#
# Usage:
#   ./existential.sh run ollama benchmark            # default: first /api/tags model
#   ./existential.sh run ollama benchmark <model>    # benchmark a specific model
#
# Runs in the existential-adhoc container (needs curl + jq + the exist network).

set -euo pipefail

# Self-elevate into existential-adhoc if we're on the host.
if [[ -z "${IN_CONTAINER:-}" ]]; then
    _SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    _REPO="$(cd "$(dirname "$_SCRIPT")/../.." && pwd)"
    exec docker compose -f "${_REPO}/existential-compose.yml" run --rm -it \
        --entrypoint "" -e IN_CONTAINER=1 \
        existential-adhoc bash "/repo${_SCRIPT#"$_REPO"}" "$@"
fi

OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}"
MODEL="${1:-}"

hr() { printf '%0.s─' {1..64}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────

command -v jq  >/dev/null 2>&1 || die "jq not found in container."
command -v curl >/dev/null 2>&1 || die "curl not found in container."

echo ""
echo "  ollama benchmark"
hr
echo ""

TAGS="$(curl -sf --max-time 10 "${OLLAMA_URL}/api/tags")" \
    || die "ollama unreachable at ${OLLAMA_URL} — is the container running?"

# Default to the first model if none was supplied.
if [[ -z "$MODEL" ]]; then
    MODEL="$(printf '%s' "$TAGS" | jq -r '.models[0].name // empty')"
    [[ -n "$MODEL" ]] || die "ollama has no models. Pull one first: ./existential.sh run ollama pull-models"
    echo "  No model given — using first available: ${MODEL}"
else
    # Warn (don't fail) if the requested model isn't in the tag list.
    if ! printf '%s' "$TAGS" | jq -e --arg m "$MODEL" '.models[] | select(.name == $m)' >/dev/null 2>&1; then
        echo "  Warning: '${MODEL}' not found in /api/tags — ollama may pull or error on first use."
    fi
    echo "  Model: ${MODEL}"
fi
echo ""

# ── Filler generator ──────────────────────────────────────────────────────────
# Repeats a ~10-token sentence N times. Matches scratch.md's tiers:
#   ~4k≈85  ~8k≈170  ~16k≈340  ~28k≈595  (sentence ≈ 10 tokens each)

SENTENCE="The quick brown fox jumped over the lazy dog. "
filler() {
    local count="$1" out=""
    local i
    for ((i = 0; i < count; i++)); do
        out+="$SENTENCE"
    done
    printf '%s' "$out"
}

# ── Run one /api/generate call, emit a results-table row ───────────────────────
# args: <label> <prompt> [num_predict]
# Prints: label | prompt tokens | generate tok/s
run_bench() {
    local label="$1" prompt="$2" num_predict="${3:-}"

    # Build the request body with jq so the prompt is always valid JSON.
    local body
    if [[ -n "$num_predict" ]]; then
        body="$(jq -n \
            --arg model "$MODEL" \
            --arg prompt "$prompt" \
            --argjson np "$num_predict" \
            '{model: $model, prompt: $prompt, stream: false, options: {num_predict: $np}}')"
    else
        body="$(jq -n \
            --arg model "$MODEL" \
            --arg prompt "$prompt" \
            '{model: $model, prompt: $prompt, stream: false}')"
    fi

    local resp
    resp="$(curl -sf --max-time 600 "${OLLAMA_URL}/api/generate" -d "$body")" || {
        printf '  %-12s  %s\n' "$label" "FAILED (request error)"
        return 0
    }

    # Surface an ollama-level error (e.g. unknown model) cleanly.
    local err
    err="$(printf '%s' "$resp" | jq -r '.error // empty')"
    if [[ -n "$err" ]]; then
        printf '  %-12s%s\n' "$label" "ERROR: ${err}"
        return 0
    fi

    # Pull the four numbers via jq; rate = count / (duration_ns / 1e9), guarded
    # against divide-by-zero. Tab-separated so bash printf does the alignment.
    local row
    row="$(printf '%s' "$resp" | jq -r '
        def rate(c; d): if (d // 0) > 0 then (c / (d / 1e9)) else 0 end;
        [ (.prompt_eval_count // 0),
          (rate(.prompt_eval_count; .prompt_eval_duration) * 10 | round / 10),
          (.eval_count // 0),
          (rate(.eval_count; .eval_duration) * 10 | round / 10)
        ] | @tsv')"

    local p_tok p_rate g_tok g_rate
    IFS=$'\t' read -r p_tok p_rate g_tok g_rate <<<"$row" || true
    printf '  %-12s%-9s%-13s%-9s%s\n' "$label" "$p_tok" "$p_rate" "$g_tok" "$g_rate"
}

# ── Header ────────────────────────────────────────────────────────────────────

printf '  %-12s%-9s%-13s%-9s%s\n' "run" "prompt" "prompt tok/s" "gen tok" "gen tok/s"
hr

# ── Baseline (short prompt) ───────────────────────────────────────────────────

run_bench "baseline" "Write a 200 word paragraph about the ocean."

# ── Context stress tests ──────────────────────────────────────────────────────
# Pad to a target context, then ask for a fixed-length summary so generate
# tok/s is directly comparable across rows.

SUMMARY=$'\nSummarize the above in one sentence.'

run_bench "~4k"  "$(filler 85)${SUMMARY}"  200
run_bench "~8k"  "$(filler 170)${SUMMARY}" 200
run_bench "~16k" "$(filler 340)${SUMMARY}" 200
run_bench "~28k" "$(filler 595)${SUMMARY}" 200

echo ""
hr
echo ""
echo "  generate tok/s is the decode-speed metric. A sharp drop between rows"
echo "  marks where the KV cache stops fitting in VRAM for ${MODEL}."
echo ""
