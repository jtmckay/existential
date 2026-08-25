#!/usr/bin/env bash
# ComfyUI Video (Image-to-Video)
#
# Generates a video via the ComfyUI WAN2.2 14B workflow using an input
# image as the first frame and text to guide the video. The prompt text
# is read from the message/spec file. Additional parameters are passed
# as env vars.
#
# Env vars:
#   width          Video width  (default: 640)
#   height         Video height (default: 640)
#   input_image    First-frame image filename as known to ComfyUI (required)
#   output_prefix  Output filename prefix (required)
#   api_url        ComfyUI API URL (default: http://comfyui:8188/api/prompt)
set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "comfy-video-i2v" "curl not found"
    command -v jq   >/dev/null 2>&1 || precheck_fail "comfy-video-i2v" "jq not found"
    [ -f "$(dirname "${BASH_SOURCE[0]}")/../lib/comfy/video_i2v_wan2.2_14B_long.json" ] \
        || precheck_fail "comfy-video-i2v" "workflow template video_i2v_wan2.2_14B_long.json not found"
    precheck_pass "comfy-video-i2v"
    exit 0
fi

# Decree parameters
spec_file="${spec_file:-}"
message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

# ComfyUI parameters
width="${width:-640}"
height="${height:-640}"
input_image="${input_image:-}"
output_prefix="${output_prefix:-}"
api_url="${api_url:-http://comfyui:8188/api/prompt}"

# Align to nearest multiple of 16 (required by diffusion models)
align16() { echo $(( (($1 + 8) / 16) * 16 )); }
width=$(align16 "$width")
height=$(align16 "$height")

# Strip YAML frontmatter (--- delimited) and leading blank lines.
# If no frontmatter is present, returns the entire file.
read_body() {
    local has_fm
    has_fm=$(head -1 "$1")
    if [ "$has_fm" = "---" ]; then
        awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$1" | sed '/\S/,$!d'
    else
        sed '/\S/,$!d' "$1"
    fi
}

# Read prompt text from spec or message file
if [ -n "$spec_file" ] && [ -f "$spec_file" ]; then
    prompt_text=$(read_body "$spec_file")
elif [ -n "$message_file" ] && [ -f "$message_file" ]; then
    prompt_text=$(read_body "$message_file")
else
    echo "Error: No spec or message file provided"
    exit 1
fi

if [ -z "$prompt_text" ]; then
    echo "Error: Prompt text is empty"
    exit 1
fi
if [ -z "$input_image" ]; then
    echo "Error: input_image env var is required"
    exit 1
fi
if [ -z "$output_prefix" ]; then
    echo "Error: output_prefix env var is required"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../lib/comfy/video_i2v_wan2.2_14B_long.json"

if [ ! -f "$TEMPLATE" ]; then
    echo "Error: Template not found at $TEMPLATE"
    exit 1
fi

echo "=== ComfyUI WAN2.2 Video (Image-to-Video) ==="
echo "  Prompt:   ${prompt_text:0:80}..."
echo "  Image:    $input_image"
echo "  Size:     ${width}x${height}"
echo "  Output:   $output_prefix"
echo "  API:      $api_url"

PAYLOAD=$(jq \
  --arg text "$prompt_text" \
  --arg image "$input_image" \
  --argjson width "$width" \
  --argjson height "$height" \
  --arg output "$output_prefix" \
  '
  # Update prompt (execution data)
  .prompt["93"].inputs.text = $text |
  .prompt["97"].inputs.image = $image |
  .prompt["98"].inputs.width = $width |
  .prompt["98"].inputs.height = $height |
  .prompt["108"].inputs.filename_prefix = $output |

  # Update workflow (UI metadata)
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 93)).widgets_values[0] = $text |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 97)).widgets_values[0] = $image |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 98)).widgets_values[0] = $width |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 98)).widgets_values[1] = $height |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 108)).widgets_values[0] = $output
  ' "$TEMPLATE")

# Log payload for debugging
if [ -n "$message_dir" ] && [ -d "$message_dir" ]; then
    echo "$PAYLOAD" > "${message_dir}/comfy-payload.json"
    echo "  Payload:  ${message_dir}/comfy-payload.json"
fi

# Verify the payload has correct values before sending
echo "=== Payload verification ==="
echo "$PAYLOAD" | jq '{
  text_preview: (.prompt["93"].inputs.text[:60] + "..."),
  input_image: .prompt["97"].inputs.image,
  video_size: "\(.prompt["98"].inputs.width)x\(.prompt["98"].inputs.height)",
  output: .prompt["108"].inputs.filename_prefix,
  wf_i2v: "\(.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 98) | .widgets_values)"
}'

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$api_url" \
  -H 'Content-Type: application/json' \
  --data-raw "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo "=== Response (HTTP $HTTP_CODE) ==="
echo "$BODY"

if [ -n "$message_dir" ] && [ -d "$message_dir" ]; then
    echo "$BODY" > "${message_dir}/comfy-response.json"
fi

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    exit 0
else
    exit 1
fi
