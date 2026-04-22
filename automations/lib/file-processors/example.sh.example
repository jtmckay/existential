#!/usr/bin/env bash
# Example file processor — copy/rename this file to add a new type.
#
# PATTERN is matched against FILE_SOURCE, the full rclone path:
#   "<rclone_src>:<bucket>/<object-key>"   e.g. "nextcloud:photos/2024/img.jpg"
#
# All matching processors run for a given file — patterns are not exclusive.
# This script is called by file-processor after the file is downloaded (or after a
# signed URL is generated when FILE_REFERENCE_ONLY=true).
# Do not delete FILE_PATH here — file-processor handles cleanup on exit.
PATTERN="nextcloud:.*\.example$"
IS_PRE_SIGNED=false

# Env vars available when this script runs:
#   FILE_SOURCE     full rclone source path     e.g. "nextcloud:path/to/file.txt"
#   FILE_KEY        path after "remote:"        e.g. "path/to/file.txt"
#   FILE_ACTION     "created" or "removed"
#   FILE_PATH       absolute local temp path    empty when FILE_ACTION is "removed"
#   PRE_SIGNED_URL  signed URL                  set when IS_PRE_SIGNED=true, otherwise empty
set -euo pipefail

if [ "$FILE_ACTION" = "removed" ]; then
    echo "Delete event for $FILE_KEY — nothing to process."
    exit 0
fi

echo "Processing: $FILE_PATH"
echo "From:       $FILE_SOURCE"

# TODO: implement processing logic here
