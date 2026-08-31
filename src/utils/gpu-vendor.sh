#!/usr/bin/env bash
# gpu-vendor.sh — which GPU is in this machine. SOURCED ONLY, never run.
#
# The companion to model-tiers.sh. That file answers "how big a model fits";
# this one answers "what silicon runs it", and it has to be asked FIRST — the
# answer "none" fixes the VRAM answer at 0, so asking for a VRAM number before
# knowing whether there is a card is asking a question that may not apply.
#
# Consumed by src/quest.sh (the first-run questions) and src/lib/models.sh
# (`./existential.sh run models`, to change your mind later). The value lands in
# .env.shared as EXIST_GPU_VENDOR and is read by src/generate-compose.ts, which
# is where a vendor actually changes the generated compose file.
#
# ── Why this is a separate question from VRAM ────────────────────────────────
#
# Before this existed, EXIST_VRAM_GB=0 was overloaded to mean both "no GPU" and
# "CPU-only tier". That works for stripping nvidia reservations, but it cannot
# express the third case: a card that is not nvidia. An AMD card has plenty of
# VRAM and still must not get a `driver: nvidia` reservation.
#
# ── What each vendor does to the compose file ────────────────────────────────
#
#   nvidia  Nothing. The templates already declare
#           `deploy.resources.reservations.devices: [{driver: nvidia, ...}]`,
#           which is correct for the majority case, so it ships as the default
#           and generate-compose.ts leaves it alone.
#
#   amd     The nvidia reservation is stripped (docker refuses to create a
#           container whose device driver it cannot satisfy — see
#           stripGpuReservations in generate-compose.ts) and each service's
#           `x-exist-gpu.amd` block is merged in instead. That block lives with
#           the service, so adding AMD support to a service is editing that
#           service's template, not this file.
#
#   none    The nvidia reservation is stripped and `x-exist-gpu.none` is merged
#           if the service defines one. EXIST_VRAM_GB is forced to 0, which
#           picks the CPU model tier.
#
#   external  Same compose treatment as `none` — this machine has no card to
#           reserve. What differs is intent: the models run on ANOTHER box's
#           ollama, named by EXIST_OLLAMA_URL. So quest still asks for VRAM,
#           because the question is about the REMOTE machine's card, and it
#           disables EXIST_IS_AI_OLLAMA because nothing local serves models —
#           see vendor_disabled_services below, which is where that rule lives.
#           This is also what makes Core testable end to end on a GPU-less
#           runner: everything else is real, only the model is remote.
#
# ── Adding a vendor ──────────────────────────────────────────────────────────
# Add a row here, then give the services that care an `x-exist-gpu.<slug>` block
# in their docker-compose.exist.yml. generate-compose.ts needs no change: it
# looks the vendor up by name rather than switching on a fixed set.
#
# Fields, tab-separated:
#   slug   the value stored in EXIST_GPU_VENDOR, and the x-exist-gpu key
#   label  shown in the picker
#   note   the consequence, in the picker line

GPU_VENDOR_DEFAULT="nvidia"

GPU_VENDORS=(
    "nvidia	NVIDIA	CUDA through the nvidia container runtime — the best-supported path"
    "amd	AMD	Vulkan/ROCm — works, but see the note below about privileged containers"
    "none	No GPU (CPU only)	everything runs on the CPU; expect seconds per token, not tokens per second"
    "external	Ollama on another machine	no card needed here; models come from EXIST_OLLAMA_URL"
)

# ── Services a vendor forbids ────────────────────────────────────────────────
#
# A vendor answer is not only about device reservations: `external` also means
# "the models live on another box", and a local ollama under that answer is
# strictly harmful. It serves nothing (hermes and friends read EXIST_OLLAMA_URL),
# and decree still runs the pull migrations, so it drags multi-GB
# models onto a machine that will never query them.
#
# This rule used to be written out at each call site, and the call sites drifted:
# quest.sh applied it when the vendor question was first answered, then Core's
# own service list turned EXIST_IS_AI_OLLAMA straight back on seconds later;
# `run models` never applied it at all; and e2e.sh carried a private copy so the
# harness stayed correct while real installs did not. One list, three consumers.
#
# vendor_disabled_services <slug> — EXIST_IS_* vars that must stay false under
# this vendor, one per line. Empty for a vendor with no such rule.
vendor_disabled_services() {
    case "$1" in
        external) printf '%s\n' EXIST_IS_AI_OLLAMA ;;
        *)        : ;;
    esac
}

# vendor_forbids_service <slug> <var> — true when <vendor> forbids <var>.
vendor_forbids_service() {
    vendor_disabled_services "$1" | grep -qxF "$2"
}

# gpu_vendor_row <slug> — echo the raw tab-separated row, or return 1.
gpu_vendor_row() {
    local want="$1" row
    for row in "${GPU_VENDORS[@]}"; do
        [[ "${row%%	*}" == "$want" ]] && { printf '%s\n' "$row"; return 0; }
    done
    return 1
}

# gpu_vendor_is_valid <slug> — true if the slug names a vendor we know.
gpu_vendor_is_valid() { gpu_vendor_row "$1" >/dev/null 2>&1; }

# gpu_vendor_lines — one human-readable line per vendor, tab-prefixed with the
# slug so a picker can split on it.
gpu_vendor_lines() {
    local row slug label note
    for row in "${GPU_VENDORS[@]}"; do
        IFS=$'\t' read -r slug label note <<< "$row"
        printf '%s\t%-20s %s\n' "$slug" "$label" "$note"
    done
}

# gpu_vendor_pick [current] — show the vendor picker, echo the chosen slug on
# stdout (nothing if the user aborts). All chrome goes to stderr so the caller
# can capture stdout cleanly. Needs fzf, which the adhoc container has.
#
# As in model_tier_pick: do NOT redirect fzf's stderr. fzf draws its entire
# interface there and reserves stdout for the selection, so `2>/dev/null` leaves
# it running invisibly, waiting for a keypress — indistinguishable from a hang.
gpu_vendor_pick() {
    local current="${1:-$GPU_VENDOR_DEFAULT}" pos=1 i=0 row out
    for row in "${GPU_VENDORS[@]}"; do
        i=$(( i + 1 ))
        [[ "${row%%	*}" == "$current" ]] && pos="$i"
    done

    out=$(gpu_vendor_lines | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --layout=reverse \
        --header="  What kind of GPU does this machine have?
  ↑↓ navigate   Enter confirm

  This decides how the GPU services are wired. Pick No GPU and everything
  still runs — on the CPU, with the smallest models — and you are not asked
  about VRAM. AMD needs a privileged container for GPU access.

  Pick Ollama on another machine if the models live on a different box: no
  local ollama is started, and the VRAM question is about THAT machine.
  Change it later with: ./existential.sh run models" \
        --prompt="GPU ❯ " \
        --no-info \
        --bind "start:pos(${pos})") || return 0

    [[ -n "$out" ]] && printf '%s\n' "${out%%	*}"
}
