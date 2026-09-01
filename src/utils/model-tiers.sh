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
# The KV cache grows with context, and a context that does not fit is the failure
# mode people actually hit: it presents as the model quietly forgetting its
# instructions, not as an error. num_ctx is therefore not a per-tier dial — it is
# a constant floor the whole table obeys (see rule 3).
#
# Three hard rules the table obeys:
#
#   1. The chat model MUST support tool calling, or hermes can talk but not act.
#      Every tag here has ollama's "tools" capability.
#   2. The chat model is also the vision model. Every tag here is multimodal, so
#      OCR and image chat reuse the already-resident model instead of evicting
#      it — which is what a separate llava would do on any card this size.
#   3. Every tier is at least 64k context, because hermes refuses to start an
#      agent below 64,000 tokens ("context window ... below the minimum 64,000
#      required by Hermes Agent") — it reads the number from its own config.yaml,
#      so the check fires before ollama is ever asked. No tier was cut to
#      meet this. On the small tiers the KV cache spills out of VRAM into system
#      RAM and ollama offloads layers to the CPU — that is a speed cost, not a
#      correctness one, so a 6 GB card still runs the whole stack, just slowly.
#      src/test/unit/test-model-tiers.sh enforces the floor.
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
# reservations. Expect seconds per token; the wyoming voice services are
# unaffected because they already run on CPU. It carries the same 64k context as
# every other tier — with no card the KV cache was always going to live in system
# RAM, so the floor costs it nothing it was not already paying.
#
# You do not normally reach gb=0 through this picker. The GPU vendor question
# (src/utils/gpu-vendor.sh) is asked first, and answering "No GPU" sets
# EXIST_VRAM_GB=0 directly and skips the VRAM question — a VRAM number is not a
# meaningful thing to ask someone with no card. The tier stays in the table
# because it is still the row that defines what CPU-only *runs*, and because
# `run models` can select it deliberately. Callers that have already
# established there is a GPU pass --gpu-only to hide it.
#
# gb=96 is the only tier that runs the weights at full precision (bf16) rather
# than quantised, which is what the extra memory actually buys. 63 GB of weights
# leaves roughly 30 GB for the KV cache, so it is also the only tier that goes
# past the 64k floor — 128k, comfortably in VRAM rather than spilling.

MODEL_TIER_EMBED="bge-m3"
MODEL_TIER_EMBED_DIM="1024"
MODEL_TIER_DEFAULT_GB="8"

MODEL_TIERS=(
    "0	None (CPU)	qwen3-vl:2b	65536	1.9 GB	no GPU — hermes fits, but expect seconds per token, not tokens per second"
    "6	6 GB	qwen3-vl:4b	65536	3.3 GB	e.g. RTX 3060 6GB — the 64k KV cache spills to system RAM; it works, slowly"
    "8	8 GB	gemma4:e2b-it-qat	65536	4.3 GB	e.g. RTX 3070 / 4060 — the recommended baseline; KV cache is a tight fit"
    "12	12 GB	gemma4:e4b-it-qat	65536	6.1 GB	e.g. RTX 3060 12GB / 4070 — first tier where 64k fits comfortably"
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

# model_tier_lines [--gpu-only] — echo one human-readable line per tier,
# tab-prefixed with the gb value so a picker can split on it. With --gpu-only
# the CPU tier (gb=0) is omitted: the caller already knows a GPU is present,
# because the vendor question was answered before this one.
model_tier_lines() {
    local gpu_only=false
    [[ "${1:-}" == "--gpu-only" ]] && gpu_only=true

    local row gb label chat ctx size note
    for row in "${MODEL_TIERS[@]}"; do
        IFS=$'\t' read -r gb label chat ctx size note <<< "$row"
        $gpu_only && [[ "$gb" == "0" ]] && continue
        printf '%s\t%-11s %-24s %-8s ctx %-7s %s\n' \
            "$gb" "$label" "$chat" "$size" "$ctx" "$note"
    done
}

# model_tier_pick [current_gb] [--gpu-only] — show the tier picker, echo the
# chosen gb on stdout (nothing if the user aborts). --gpu-only hides the CPU
# tier, for callers that already know a GPU is present. All chrome goes to stderr so the caller
# can capture stdout cleanly. Needs fzf, which the adhoc container has.
#
# Do NOT redirect fzf's stderr here. fzf renders its whole interface on stderr
# (stdout is reserved for the selection, which is the point of the design), so
# a `2>/dev/null` leaves fzf running and waiting for a keypress with nothing on
# screen — indistinguishable from a hang. Every other picker in the repo leaves
# stderr alone; this one is captured for its stdout, which is what made the
# redirect look harmless.
model_tier_pick() {
    local current="${1:-$MODEL_TIER_DEFAULT_GB}" pos=1 i=0 gb out
    local -a filter=()
    [[ "${2:-}" == "--gpu-only" ]] && filter=(--gpu-only)

    # Position the cursor by counting the rows the picker will actually show,
    # not every row in the table — under --gpu-only the CPU tier is gone and a
    # table-index would land one row low.
    while IFS=$'\t' read -r gb _; do
        i=$(( i + 1 ))
        [[ "$gb" == "$current" ]] && pos="$i"
    done < <(model_tier_lines "${filter[@]}")

    out=$(model_tier_lines "${filter[@]}" | fzf \
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
        --bind "start:pos(${pos})") || return 0

    [[ -n "$out" ]] && printf '%s\n' "${out%%	*}"
}
