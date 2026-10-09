#!/usr/bin/env bash
# ComfyUI
#
# Generates an image or video via ComfyUI. `type` names a workflow binding in
# ../lib/comfy/workflows/ — run with an unknown type to list them. Adding a flow
# is adding a .json and a .yml there; this routine needs no change.
#
# The message body is the prompt. For a batch flow (one whose binding declares
# `items`, e.g. image-qwen-angles) the body is instead a YAML list of
# {prompt, output} — see that binding's header for the shape.
#
# Every other parameter is named by the binding and read from an env var of the
# same name; leaving one unset keeps the workflow's own value. Common ones:
#   width / height   output size (image/WAN flows, and an override on LTX)
#   aspect_ratio     e.g. "16:9 (Widescreen)"   } LTX size, via ResolutionSelector
#   megapixels       e.g. 0.9                   }
#   duration / fps   video length in seconds, and frame rate (LTX)
#   seed             noise seed (default: random). `noise_seed` also accepted.
#   input_image      image filename known to ComfyUI, "sub/foo.png [input]" form ok
#   last_image       final-frame image (video-ltx-first-last)
#   output_prefix    output filename prefix (required)
#   items_file       path to the YAML item list, instead of the message body
#   api_url          ComfyUI API URL (default: EXIST_COMFYUI_URL + /api/prompt)
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib/comfy" && pwd)"
# shellcheck source=../lib/comfy/common.sh
source "$LIB_DIR/common.sh"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    for cmd in curl jq yq tsx; do
        command -v "$cmd" >/dev/null 2>&1 || precheck_fail "comfy" "$cmd not found"
    done
    for binding in "$LIB_DIR"/workflows/*.yml; do
        [ -f "$binding" ] || precheck_fail "comfy" "no workflow bindings in $LIB_DIR/workflows"
        workflow=$(yq -r '.workflow' "$binding")
        [ -f "$LIB_DIR/workflows/$workflow" ] \
            || precheck_fail "comfy" "$(basename "$binding") names a missing workflow: $workflow"
    done
    precheck_pass "comfy"
    exit 0
fi

# Decree parameters
spec_file="${spec_file:-}"
message_file="${message_file:-}"
message_dir="${message_dir:-}"

# ComfyUI parameters
type="${type:-image-text}"
items_file="${items_file:-}"
api_url="${api_url:-${EXIST_COMFYUI_URL:-http://comfyui:8188}/api/prompt}"
# noise_seed was this routine's name for it before the bindings existed.
seed="${seed:-${noise_seed:-}}"

binding="$LIB_DIR/workflows/${type}.yml"
if [ ! -f "$binding" ]; then
    echo "Error: unknown type '$type'. Available:"
    for f in "$LIB_DIR"/workflows/*.yml; do echo "  $(basename "$f" .yml)"; done
    exit 1
fi

body=$(comfy_prompt_text "$spec_file" "$message_file") || exit 1
if [ -n "$items_file" ]; then
    [ -f "$items_file" ] || { echo "Error: items_file not found: $items_file"; exit 1; }
    body=$(comfy_read_body "$items_file")
fi
if [ -z "$body" ]; then
    echo "Error: message body is empty"
    exit 1
fi

# Every param the binding declares, picked up from the env var of the same name.
# `prompt` is the body, not an env var, so it is skipped here.
patch_input=$(jq -n '{params: {}, items: []}')
while read -r name; do
    [ "$name" = "prompt" ] && continue
    value="${!name:-}"
    [ -n "$value" ] || continue
    patch_input=$(jq --arg k "$name" --arg v "$value" '.params[$k] = $v' <<<"$patch_input")
done < <(yq -r '.params // {} | keys | .[]' "$binding")

if yq -e '.items' "$binding" >/dev/null 2>&1; then
    items=$(yq -o=json -I=0 '.' <<<"$body") \
        || { echo "Error: message body is not a YAML list of {prompt, output}"; exit 1; }
    patch_input=$(jq --argjson items "$items" '.items = $items' <<<"$patch_input")
else
    patch_input=$(jq --arg text "$body" '.params.prompt = $text' <<<"$patch_input")
fi

echo "=== ComfyUI: $type ==="
echo "  API:      $api_url"
payload=$(tsx "$LIB_DIR/patch.ts" "$binding" <<<"$patch_input")

comfy_submit "$payload" "$api_url" "$message_dir"

if [ "$COMFY_HTTP_CODE" -ge 200 ] && [ "$COMFY_HTTP_CODE" -lt 300 ]; then
    exit 0
else
    exit 1
fi
