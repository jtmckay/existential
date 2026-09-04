#!/usr/bin/env bash
# ComfyUI
#
# Generates an image or video via ComfyUI. `type` selects which subroutine
# (and workflow template) runs; the prompt text is always read from the
# message/spec file:
#   image-text        text prompt only        (default: 400x400)
#   image-text-image  text prompt + ref image  (default: 1024x1024, needs input_image)
#   video-i2v         image-to-video           (default: 640x640, needs input_image)
#
# Env vars:
#   type           image-text | image-text-image | video-i2v (default: image-text)
#   width          Output width  (default: per-type, see above)
#   height         Output height (default: per-type, see above)
#   noise_seed     Noise seed for reproducibility (default: random; image types only)
#   input_image    Reference/first-frame image filename known to ComfyUI
#                  (required for image-text-image and video-i2v)
#   output_prefix  Output filename prefix (required)
#   api_url        ComfyUI API URL (default: http://comfyui:8188/api/prompt)
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib/comfy" && pwd)"
# shellcheck source=../lib/comfy/common.sh
source "$LIB_DIR/common.sh"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "comfy" "curl not found"
    command -v jq   >/dev/null 2>&1 || precheck_fail "comfy" "jq not found"
    command -v shuf >/dev/null 2>&1 || precheck_fail "comfy" "shuf not found"
    for f in image_flux2_text_landscape.json image_flux2_text_image.json video_i2v_wan2.2_14B_long.json; do
        [ -f "$LIB_DIR/$f" ] || precheck_fail "comfy" "workflow template $f not found"
    done
    precheck_pass "comfy"
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
type="${type:-image-text}"
width="${width:-}"
height="${height:-}"
noise_seed="${noise_seed:-}"
input_image="${input_image:-}"
output_prefix="${output_prefix:-}"
api_url="${api_url:-http://comfyui:8188/api/prompt}"

if [ -z "$output_prefix" ]; then
    echo "Error: output_prefix env var is required"
    exit 1
fi

prompt_text=$(comfy_prompt_text "$spec_file" "$message_file") || exit 1
if [ -z "$prompt_text" ]; then
    echo "Error: Prompt text is empty"
    exit 1
fi

# --- Subroutines -------------------------------------------------------

# Text prompt only, via the FLUX2 workflow.
subroutine_image_text() {
    width=$(comfy_align16 "${width:-400}")
    height=$(comfy_align16 "${height:-400}")

    local seed seed_control
    if [ -z "$noise_seed" ]; then
        seed=$(shuf -i 1-999999999999999 -n 1)
        seed_control="randomize"
    else
        seed="$noise_seed"
        seed_control="fixed"
    fi

    echo "=== ComfyUI FLUX2 Image (Text Only) ==="
    echo "  Prompt:   ${prompt_text:0:80}..."
    echo "  Size:     ${width}x${height}"
    echo "  Seed:     $seed"
    echo "  Output:   $output_prefix"
    echo "  API:      $api_url"

    local payload
    payload=$(jq \
      --arg text "$prompt_text" \
      --argjson width "$width" \
      --argjson height "$height" \
      --argjson seed "$seed" \
      --arg seed_control "$seed_control" \
      --arg output "$output_prefix" \
      '
      # Update prompt (execution data)
      .prompt["6"].inputs.text = $text |
      .prompt["25"].inputs.noise_seed = $seed |
      .prompt["47"].inputs.width = $width |
      .prompt["47"].inputs.height = $height |
      .prompt["48"].inputs.width = $width |
      .prompt["48"].inputs.height = $height |
      .prompt["9"].inputs.filename_prefix = $output |

      # Update workflow (UI metadata) — must stay in sync with prompt
      # for the workflow to load correctly when opened from the saved image
      (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 6)).widgets_values[0] = $text |
      (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 25)).widgets_values = [$seed, $seed_control] |
      (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 47)).widgets_values = [$width, $height, 1] |
      (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 48)).widgets_values = [20, $width, $height] |
      (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 50)).widgets_values[0] = $width |
      (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 51)).widgets_values[0] = $height |
      (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 9)).widgets_values[0] = $output
      ' "$LIB_DIR/image_flux2_text_landscape.json")

    echo "=== Payload verification ==="
    echo "$payload" | jq '{
      text_preview: (.prompt["6"].inputs.text[:60] + "..."),
      noise_seed: .prompt["25"].inputs.noise_seed,
      latent_size: "\(.prompt["47"].inputs.width)x\(.prompt["47"].inputs.height)",
      scheduler_size: "\(.prompt["48"].inputs.width)x\(.prompt["48"].inputs.height)",
      output: .prompt["9"].inputs.filename_prefix,
      wf_seed: (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 25) | .widgets_values),
      wf_latent: (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 47) | .widgets_values),
      wf_sched: (.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 48) | .widgets_values)
    }'

    comfy_submit "$payload" "$api_url" "$message_dir"
}

# Text prompt + reference image, via the FLUX2 workflow.
subroutine_image_text_image() {
    if [ -z "$input_image" ]; then
        echo "Error: input_image env var is required for type=image-text-image"
        exit 1
    fi

    width=$(comfy_align16 "${width:-1024}")
    height=$(comfy_align16 "${height:-1024}")

    local seed seed_control
    if [ -z "$noise_seed" ]; then
        seed=$(shuf -i 1-999999999999999 -n 1)
        seed_control="randomize"
    else
        seed="$noise_seed"
        seed_control="fixed"
    fi

    # Parse image reference: "path/file.png [folder_type]" or just "path/file.png"
    # The API prompt uses the full string; the workflow widget needs [name, type] split.
    local image_name image_type
    if [[ "$input_image" =~ ^(.*)[[:space:]]+\[([a-z]+)\]$ ]]; then
        image_name="${BASH_REMATCH[1]}"
        image_type="${BASH_REMATCH[2]}"
    else
        image_name="$input_image"
        image_type="image"
    fi

    echo "=== ComfyUI FLUX2 Image (Text + Reference Image) ==="
    echo "  Prompt:   ${prompt_text:0:80}..."
    echo "  Image:    $input_image"
    echo "  Size:     ${width}x${height}"
    echo "  Seed:     $seed"
    echo "  Output:   $output_prefix"
    echo "  API:      $api_url"

    local payload
    payload=$(jq \
      --arg text "$prompt_text" \
      --arg image "$input_image" \
      --arg image_name "$image_name" \
      --arg image_type "$image_type" \
      --argjson width "$width" \
      --argjson height "$height" \
      --argjson seed "$seed" \
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
      ' "$LIB_DIR/image_flux2_text_image.json")

    echo "=== Payload verification ==="
    echo "$payload" | jq '{
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

    comfy_submit "$payload" "$api_url" "$message_dir"
}

# Image-to-video, via the WAN2.2 14B workflow.
subroutine_video_i2v() {
    if [ -z "$input_image" ]; then
        echo "Error: input_image env var is required for type=video-i2v"
        exit 1
    fi

    width=$(comfy_align16 "${width:-640}")
    height=$(comfy_align16 "${height:-640}")

    echo "=== ComfyUI WAN2.2 Video (Image-to-Video) ==="
    echo "  Prompt:   ${prompt_text:0:80}..."
    echo "  Image:    $input_image"
    echo "  Size:     ${width}x${height}"
    echo "  Output:   $output_prefix"
    echo "  API:      $api_url"

    local payload
    payload=$(jq \
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
      ' "$LIB_DIR/video_i2v_wan2.2_14B_long.json")

    echo "=== Payload verification ==="
    echo "$payload" | jq '{
      text_preview: (.prompt["93"].inputs.text[:60] + "..."),
      input_image: .prompt["97"].inputs.image,
      video_size: "\(.prompt["98"].inputs.width)x\(.prompt["98"].inputs.height)",
      output: .prompt["108"].inputs.filename_prefix,
      wf_i2v: "\(.extra_data.extra_pnginfo.workflow.nodes[] | select(.id == 98) | .widgets_values)"
    }'

    comfy_submit "$payload" "$api_url" "$message_dir"
}

# --- Dispatch ------------------------------------------------------------

case "$type" in
    image-text)       subroutine_image_text ;;
    image-text-image) subroutine_image_text_image ;;
    video-i2v)        subroutine_video_i2v ;;
    *)
        echo "Error: unknown type '$type' (expected image-text | image-text-image | video-i2v)"
        exit 1
        ;;
esac

if [ "$COMFY_HTTP_CODE" -ge 200 ] && [ "$COMFY_HTTP_CODE" -lt 300 ]; then
    exit 0
else
    exit 1
fi
