#!/usr/bin/env bash
# Transcribe audio files via Whisper.
#
# Matches mp3, mp4, and wav (case-insensitive). Skips the local download and instead
# uses a pre-signed URL to stream the audio directly to the Whisper API.
# Saves the transcription to the same rclone key with FILE_SUFFIX appended.
PATTERN='\.[Mm][Pp][34]$|\.[Ww][Aa][Vv]$'
IS_PRE_SIGNED=true

# Configuration — override via env or message frontmatter
FILE_SUFFIX="${FILE_SUFFIX:-.transcription.txt}"
OUTPUT_RCLONE="${OUTPUT_RCLONE:-nextcloud}"
export WHISPER_MODEL="${WHISPER_MODEL:-}"

# Env vars from file-processor:
#   FILE_SOURCE     full rclone source path
#   FILE_KEY        path after "remote:"        e.g. "bucket/recordings/meeting.mp3"
#   FILE_ACTION     "created" or "removed"
#   FILE_PATH       empty (IS_PRE_SIGNED=true skips download)
#   PRE_SIGNED_URL  signed URL for the audio file
set -euo pipefail

if [ "$FILE_ACTION" = "removed" ]; then
    echo "Delete event for $FILE_KEY — nothing to transcribe."
    exit 0
fi

if [ -z "$PRE_SIGNED_URL" ]; then
    echo "PRE_SIGNED_URL is empty — cannot transcribe."
    exit 1
fi

_output_path="${OUTPUT_RCLONE}:${FILE_KEY}${FILE_SUFFIX}"
echo "Transcribing: $FILE_SOURCE"

_transcription=$(/work/.decree/lib/node_modules/.bin/tsx /work/.decree/lib/whisper-transcribe.ts)

printf '%s' "$_transcription" | rclone rcat "$_output_path" \
    --config /secrets/rclone/rclone.conf

echo "Saved: $_output_path"
