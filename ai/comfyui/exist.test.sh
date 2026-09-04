#!/usr/bin/env bash
# exist.test.sh — validate that comfyui is fully operational.
#
# See .claude/reference/testing.md for the convention.
# Run via: ./existential.sh run comfyui test  (or: ./existential.sh test)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "comfyui" EXIST_IS_AI_COMFYUI
skip_if_disabled

# ComfyUI listens on :8188 inside the container.
probe_service "comfyui /"            comfyui 8188 /            200
probe_service "comfyui /system_stats" comfyui 8188 /system_stats 200

# A 200 is not proof of a working server. /system_stats must parse and name a
# version, and /object_info must carry the node classes the comfy-* routines
# build their workflows from — a stripped or half-started install answers 200
# and then rejects every /prompt with "node type not found".
STATS=$(curl -sS --max-time 10 "http://comfyui:8188/system_stats" 2>/dev/null || true)
VERSION=$(printf '%s' "$STATS" | jq -r '.system.comfyui_version // empty' 2>/dev/null || true)
if [ -n "$VERSION" ]; then
    ok "comfyui version ${VERSION}"
else
    fail "comfyui /system_stats parses" "${STATS:-<no response>}" \
         "Not the JSON ComfyUI serves. Check: docker logs comfyui"
fi

# One node per routine family: image (comfy-image-text*), reference image
# (comfy-image-text-image), video (comfy-video-i2v).
MISSING=$(curl -sS --max-time 20 "http://comfyui:8188/object_info" 2>/dev/null \
    | jq -r '[ "EmptyFlux2LatentImage","Flux2Scheduler","ReferenceLatent",
               "WanImageToVideo","CreateVideo","SaveVideo","SaveImage","UNETLoader" ]
             - (keys) | join(" ")' 2>/dev/null || echo "?")
case "$MISSING" in
    "")  ok "comfyui core node classes" ;;
    "?") fail "comfyui core node classes" "/object_info did not return JSON" \
              "Check: docker logs comfyui" ;;
    *)   fail "comfyui core node classes" "missing: $MISSING" \
              "The image is older than the workflows in automation/lib/comfy/. Bump the pin: ./existential.sh run check-versions" ;;
esac

finish
