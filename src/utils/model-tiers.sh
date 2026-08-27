#!/usr/bin/env bash
# model-tiers.sh — VRAM tier → model selection. SOURCED ONLY, never run.
#
# One table mapping "how much VRAM do you have" to the EXIST_MODEL_* globals.
# Consumed by src/quest.sh (the first-run question) and src/lib/models.sh
# (`./existential.sh run models`, to change your mind later).
#
# ── How the sizes were picked ─────────────────────────────────────────────────
#
# Every figure is the measured Q4 download from ollama.com, not an estimate.
# The budget for a tier is:
#
#     chat model  +  embedding model (bge-m3, 1.2 GB)  +  KV cache  <  VRAM
#
# The KV cache grows with context, which is why num_ctx is part of the tier and
# not a separate knob — a context that does not fit is the failure mode people
# actually hit, and it presents as the model quietly forgetting its instructions.
#
# Two hard rules the table obeys:
#
#   1. The chat model MUST support tool calling, or hermes can talk but not act.
#      Every tag here has ollama's "tools" capability.
#   2. The chat model is also the vision model. Every tag here is multimodal, so
#      OCR and image chat reuse the already-resident model instead of evicting
#      it — which is what a separate llava would do on any card this size.
#
# A note on gemma4's "E" tags: the E in e2b/e4b is *effective* parameters, a
# claim about compute, not file size. gemma4:e4b is an 8B model that downloads
# at 9.6 GB. Use the -qat (quantization-aware trained) variants — they are much
# smaller than the plain q4 tags at comparable quality.
#
# ── Adding or changing a tier ────────────────────────────────────────────────
# Fields, tab-separated:
#   gb        the VRAM number the user picks
#   label     shown in the picker
#   chat      EXIST_MODEL_CHAT / _EXTRACT / _VISION (one multimodal model)
#   num_ctx   EXIST_MODEL_CHAT_NUM_CTX
#   size      chat model download size, for the picker line
#   note      the trade-off, in the picker line
#
# The embedding model is deliberately NOT per-tier: changing it after first
# ingestion corrupts openviking's vector index (see EXIST_MODEL_EMBED).
#
# ── The two ends of the range ────────────────────────────────────────────────
#
# gb=0 is CPU-only, and it is not just a model swap: four services declare an
# nvidia device reservation (ollama, comfyui, whisperx, chatterbox), and docker
# refuses to create a container it cannot satisfy — one of them takes down
# `docker compose up` for the whole stack. src/generate-compose.ts strips those
# reservations when EXIST_VRAM_GB=0. Expect seconds per token; the wyoming voice
# services are unaffected because they already run on CPU.
#
# gb=96 is the only tier that runs the weights at full precision (bf16) rather
# than quantised, which is what the extra memory actually buys. 63 GB of weights
# leaves roughly 30 GB for the KV cache, hence the 128k context.

MODEL_TIER_EMBED="bge-m3"
MODEL_TIER_EMBED_DIM="1024"
MODEL_TIER_DEFAULT_GB="8"

MODEL_TIERS=(
    "0	None (CPU)	qwen3-vl:2b	8192	1.9 GB	no GPU — works, but expect seconds per token, not tokens per second"
    "6	6 GB	qwen3-vl:4b	16384	3.3 GB	e.g. RTX 3060 6GB — the smallest card worth using"
    "8	8 GB	gemma4:e2b-it-qat	32768	4.3 GB	e.g. RTX 3070 / 4060 — the recommended baseline"
    "12	12 GB	gemma4:e4b-it-qat	32768	6.1 GB	e.g. RTX 3060 12GB / 4070 — more headroom, same shape"
    "16	16 GB	gemma4:12b-it-qat	65536	7.2 GB	e.g. RTX 4080 / A4000 — noticeably stronger reasoning"
    "24	24 GB	gemma4:26b-a4b-it-qat	65536	16 GB	e.g. RTX 3090 / 4090 — quantised, still very capable"
    "96	96 GB+	gemma4:31b-it-bf16	131072	63 GB	e.g. RTX 6000 Pro — full precision, no quantisation loss"
)

# model_tier_row <gb> — echo the raw tab-separated row for a tier, or return 1.
model_tier_row() {
    local want="$1" row
    for row in "${MODEL_TIERS[@]}"; do
        [[ "${row%%	*}" == "$want" ]] && { printf '%s\n' "$row"; return 0; }
    done
    return 1
}

# model_tier_env <gb> — echo the KEY=VALUE lines a tier implies, one per line.
# The caller writes them (quest.sh uses env_set); this stays pure so it can be
# tested without touching .env.shared.
model_tier_env() {
    local row chat ctx
    row="$(model_tier_row "$1")" || return 1
    IFS=$'\t' read -r _ _ chat ctx _ _ <<< "$row"
    printf 'EXIST_VRAM_GB=%s\n'              "$1"
    printf 'EXIST_MODEL_CHAT=%s\n'           "$chat"
    printf 'EXIST_MODEL_CHAT_NUM_CTX=%s\n'   "$ctx"
    # One resident model does chat, background extraction and vision. Splitting
    # them only helps once you have VRAM for two models at once.
    printf 'EXIST_MODEL_EXTRACT=%s\n'        "$chat"
    printf 'EXIST_MODEL_VISION=%s\n'         "$chat"
    printf 'EXIST_MODEL_EMBED=%s\n'          "$MODEL_TIER_EMBED"
    printf 'EXIST_MODEL_EMBED_DIM=%s\n'      "$MODEL_TIER_EMBED_DIM"
}

# model_tier_lines — echo one human-readable line per tier, tab-prefixed with
# the gb value so a picker can split on it.
model_tier_lines() {
    local row gb label chat ctx size note
    for row in "${MODEL_TIERS[@]}"; do
        IFS=$'\t' read -r gb label chat ctx size note <<< "$row"
        printf '%s\t%-11s %-24s %-8s ctx %-7s %s\n' \
            "$gb" "$label" "$chat" "$size" "$ctx" "$note"
    done
}

# model_tier_pick [current_gb] — show the tier picker, echo the chosen gb on
# stdout (nothing if the user aborts). All chrome goes to stderr so the caller
# can capture stdout cleanly. Needs fzf, which the adhoc container has.
model_tier_pick() {
    local current="${1:-$MODEL_TIER_DEFAULT_GB}" pos=1 i=0 row out
    for row in "${MODEL_TIERS[@]}"; do
        i=$(( i + 1 ))
        [[ "${row%%	*}" == "$current" ]] && pos="$i"
    done

    out=$(model_tier_lines | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --layout=reverse \
        --header="  How much VRAM does this machine's GPU have?
  ↑↓ navigate   Enter confirm

  This sizes the local models: one multimodal model handles chat, background
  memory work and images, with bge-m3 (1.2 GB) alongside it for embeddings.
  Everything can be changed later with: ./existential.sh run models" \
        --prompt="VRAM ❯ " \
        --no-info \
        --bind "start:pos(${pos})" 2>/dev/null) || return 0

    [[ -n "$out" ]] && printf '%s\n' "${out%%	*}"
}
