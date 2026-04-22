#!/usr/bin/env bash
# OCR images via Ollama vision model.
#
# Downloads the image directly (no pre-signed URL), reads it as base64, and sends
# it to Ollama for text extraction. Saves the result next to the original file.
PATTERN='\.(jpg|jpeg|png|webp|gif|heic|heif|tiff?|bmp)$'
IS_PRE_SIGNED=false

# Configuration — override via env or message frontmatter
FILE_SUFFIX="${FILE_SUFFIX:-.ocr.txt}"
OUTPUT_RCLONE="${OUTPUT_RCLONE:-nextcloud}"
export OCR_MODEL="${OCR_MODEL:-llava}"
export OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}"
PROMPT="Extract all text from this image exactly as it appears. Preserve the original formatting and line breaks. If there is no text, respond with 'No text found.'"

# Env vars from file-processor:
#   FILE_SOURCE     full rclone source path
#   FILE_KEY        path after "remote:"        e.g. "bucket/telegram/receipt.jpg"
#   FILE_ACTION     "created" or "removed"
#   FILE_PATH       absolute local temp path    set because IS_PRE_SIGNED=false
#   PRE_SIGNED_URL  empty (IS_PRE_SIGNED=false)
set -euo pipefail

if [ "$FILE_ACTION" = "removed" ]; then
    echo "Delete event for $FILE_KEY — nothing to OCR."
    exit 0
fi

_output_path="${OUTPUT_RCLONE}:${FILE_KEY}${FILE_SUFFIX}"
echo "OCR: $FILE_SOURCE → $_output_path"

_text=$(/work/.decree/lib/node_modules/.bin/tsx /work/.decree/lib/ocr.ts "$PROMPT")

printf '%s' "$_text" | rclone rcat "$_output_path" \
    --config /secrets/rclone/rclone.conf

echo "Saved: $_output_path"
