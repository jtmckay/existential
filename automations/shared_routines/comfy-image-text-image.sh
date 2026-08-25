#!/usr/bin/env bash
# ComfyUI Image (Text + Reference Image)
#
# Generates an image via the ComfyUI FLUX2 workflow using a text prompt
# and a reference image. The prompt text is read from the message/spec
# file. Additional parameters are passed as env vars.
#
# Env vars:
#   width          Image width  (default: 1024)
#   height         Image height (default: 1024)
#   noise_seed     Noise seed for reproducibility (default: random)
#   input_image    Reference image filename as known to ComfyUI (required)
#   output_prefix  Output filename prefix (required)
#   api_url        ComfyUI API URL (default: http://comfyui:8188/api/prompt)
set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "comfy-image-text-image" "curl not found"
    command -v jq   >/dev/null 2>&1 || precheck_fail "comfy-image-text-image" "jq not found"
    command -v shuf >/dev/null 2>&1 || precheck_fail "comfy-image-text-image" "shuf not found"
    [ -f "$(dirname "${BASH_SOURCE[0]}")/../lib/comfy/image_flux2_text_image.json" ] \
        || precheck_fail "comfy-image-text-image" "workflow template image_flux2_text_image.json not found"
    precheck_pass "comfy-image-text-image"
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
width="${width:-1024}"
height="${height:-1024}"
noise_seed="${noise_seed:-}"
input_image="${input_image:-}"
output_prefix="${output_prefix:-}"
api_url="${api_url:-http://comfyui:8188/api/prompt}"

# Generate a random seed if not provided; track control mode for workflow UI
if [ -z "$noise_seed" ]; then
    noise_seed=$(shuf -i 1-999999999999999 -n 1)
    seed_control="randomize"
else
    seed_control="fixed"
fi

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

# Parse image reference: "path/file.png [folder_type]" or just "path/file.png"
# The API prompt uses the full string; the workflow widget needs [name, type] split.
if [[ "$input_image" =~ ^(.*)[[:space:]]+\[([a-z]+)\]$ ]]; then
    image_name="${BASH_REMATCH[1]}"
    image_type="${BASH_REMATCH[2]}"
else
    image_name="$input_image"
    image_type="image"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../lib/comfy/image_flux2_text_image.json"

if [ ! -f "$TEMPLATE" ]; then
    echo "Error: Template not found at $TEMPLATE"
    exit 1
fi

echo "=== ComfyUI FLUX2 Image (Text + Reference Image) ==="
echo "  Prompt:   ${prompt_text:0:80}..."
echo "  Image:    $input_image"
echo "  Size:     ${width}x${height}"
echo "  Seed:     $noise_seed"
echo "  Output:   $output_prefix"
echo "  API:      $api_url"

PAYLOAD=$(jq \
  --arg text "$prompt_text" \
  --arg image "$input_image" \
  --arg image_name "$image_name" \
  --arg image_type "$image_type" \
  --argjson width "$width" \
  --argjson height "$height" \
  --argjson seed "$noise_seed" \
  --arg seed_control "$seed_control" \
  --arg output "$output_prefix" \
  '
  # Update prompt (execution data)
  .prompt["6"].inputs.text = $text |
  .prompt["25"].inputs.noise_seed = $seed |
  .prompt["46"].inputs.image = $image |
  .prompt["47"].inputs.width = $width |
  .prompt["47"].inputs.height = $height |
  .prompt["48"].inputs.width = $width |
  .prompt["48"].inputs.height = $height |
  .prompt["9"].inputs.filename_prefix = $output |

  # Update workflow (UI metadata) — must stay in sync with prompt
  # for the workflow to load correctly when opened from the saved image
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 6)).widgets_values[0] = $text |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 25)).widgets_values = [$seed, $seed_control] |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 46)).widgets_values = [$image_name, $image_type] |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 47)).widgets_values = [$width, $height, 1] |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 48)).widgets_values = [20, $width, $height] |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 50)).widgets_values[0] = $width |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 51)).widgets_values[0] = $height |
  (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 9)).widgets_values[0] = $output
  ' "$TEMPLATE")

# Log payload for debugging
if [ -n "$message_dir" ] && [ -d "$message_dir" ]; then
    echo "$PAYLOAD" > "${message_dir}/comfy-payload.json"
    echo "  Payload:  ${message_dir}/comfy-payload.json"
fi

# Verify the payload has correct values before sending
echo "=== Payload verification ==="
echo "$PAYLOAD" | jq '{
  text_preview: (.prompt["6"].inputs.text[:60] + "..."),
  noise_seed: .prompt["25"].inputs.noise_seed,
  input_image: .prompt["46"].inputs.image,
  latent_size: "\(.prompt["47"].inputs.width)x\(.prompt["47"].inputs.height)",
  scheduler_size: "\(.prompt["48"].inputs.width)x\(.prompt["48"].inputs.height)",
  output: .prompt["9"].inputs.filename_prefix,
  wf_seed: (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 25) | .widgets_values),
  wf_image: (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 46) | .widgets_values),
  wf_latent: (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 47) | .widgets_values),
  wf_sched: (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 48) | .widgets_values)
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
