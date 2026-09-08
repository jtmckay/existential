#!/usr/bin/env bash
# exist.test.sh — validate that comfyui is fully operational.
#
# See .claude/reference/testing.md for the convention.
# Run via: ./existential.sh run comfyui test  (or: ./existential.sh test)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "comfyui" EXIST_IS_AI_COMFYUI

# ComfyUI is either the local container or a server on another machine — the
# comfy routine and caddy both follow EXIST_COMFYUI_URL, so this test does too.
# At the default URL it is the local container: skip when disabled, and probe
# through every layer. Anywhere else it is what the routine actually talks to,
# so it is checked regardless of the enablement flag.
load_env_exist
COMFY_URL="${EXIST_COMFYUI_URL:-http://comfyui:8188}"
COMFY_URL="${COMFY_URL%/}"

if [ "$COMFY_URL" = "http://comfyui:8188" ]; then
    skip_if_disabled
    # ComfyUI listens on :8188 inside the container.
    probe_service "comfyui /"            comfyui 8188 /            200
    probe_service "comfyui /system_stats" comfyui 8188 /system_stats 200
else
    ok "comfyui is external — ${COMFY_URL}"
    http_probe "comfyui /"             "${COMFY_URL}/"             200
    http_probe "comfyui /system_stats" "${COMFY_URL}/system_stats" 200
fi

# A 200 is not proof of a working server. /system_stats must parse and name a
# version, and /object_info must carry the node classes the comfy routine's
# workflows are built from — a stripped or half-started install answers 200 and
# then rejects every /prompt with "node type not found".
STATS=$(curl -sS --max-time 10 "${COMFY_URL}/system_stats" 2>/dev/null || true)
VERSION=$(printf '%s' "$STATS" | jq -r '.system.comfyui_version // empty' 2>/dev/null || true)
if [ -n "$VERSION" ]; then
    ok "comfyui version ${VERSION}"
else
    fail "comfyui /system_stats parses" "${STATS:-<no response>}" \
         "Not the JSON ComfyUI serves. Check: docker logs comfyui"
fi

# Every class every shipped workflow uses, read out of the workflows themselves
# rather than listed here — so a new flow extends this assertion by existing.
# Custom nodes are the reason this matters: several workflows lean on packs
# (ResolutionSelector, the LTXV and ComfyMath nodes) that live in the comfyui_data
# volume via ComfyUI Manager, not in the image, and so are absent on a fresh host.
WORKFLOWS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../automation/lib/comfy/workflows" && pwd)"
NEEDED=$(jq -s -r '[ .[] | (.prompt // .) | .[].class_type ] | unique' "$WORKFLOWS"/*.json)
MISSING=$(curl -sS --max-time 20 "${COMFY_URL}/object_info" 2>/dev/null \
    | jq -r --argjson needed "$NEEDED" '$needed - (keys) | join(" ")' 2>/dev/null || echo "?")
case "$MISSING" in
    "")  ok "comfyui node classes for every shipped workflow" ;;
    "?") fail "comfyui node classes for every shipped workflow" "/object_info did not return JSON" \
              "Check: docker logs comfyui" ;;
    *)   fail "comfyui node classes for every shipped workflow" "missing: $MISSING" \
              "Either the image predates the workflows (bump the pin: ./existential.sh run check-versions) or a custom node pack is not installed — add it in the ComfyUI Manager." ;;
esac

finish
