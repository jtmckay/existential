#!/usr/bin/env bash
# shellcheck disable=SC2034  # PATTERN, CRITERIA and IS_PRE_SIGNED are this file's
# contract with minio-router and file-processor, which read them out of the source
# rather than by sourcing it. Nothing here consumes them.
# Example file processor — copy/rename this file to add a new type.
#
# A processor declares up to two tests, and a file must pass both to reach the
# body of the script:
#
# PATTERN (required) is matched against FILE_SOURCE, the full rclone path:
#   "<rclone_src>:<rclone_prefix>/<object-key>"  e.g. "nextcloud:S3/2024/img.jpg"
# Note the S3 BUCKET is not in there — minio-router replaces it with the
# webhook's rclone_prefix, because the path has to be valid for the rclone
# remote, not for S3. Match on the prefix and key, never on a bucket name.
# It is a plain bash regex, evaluated by minio-router. Cheap and mechanical.
#
# CRITERIA (optional) is a natural-language test of the file's CONTENT, put to
# the model by file-processor after the download. Leave it empty — as this
# example does — and the path match is the whole test, which is how every
# processor behaved before criteria existed.
#
#   CRITERIA="an invoice with a due date"
#
# It costs one model call per file that got past PATTERN, so keep PATTERN narrow
# enough that the gate is not asked about everything. The judgment is deliberately
# strict: it answers NO unless the document genuinely matches. When it matches,
# FILE_MATCH_REASON holds the model's one-line reason.
#
# Criteria only work on text. For IS_PRE_SIGNED processors and for "removed"
# events there is nothing on disk to judge, so the gate is skipped entirely and
# the processor runs on the path match alone.
#
# All matching processors run for a given file — patterns are not exclusive.
# This script is called by file-processor after the file is downloaded (or after a
# signed URL is generated when FILE_REFERENCE_ONLY=true).
# Do not delete FILE_PATH here — file-processor handles cleanup on exit.
PATTERN="nextcloud:.*\.txt"
CRITERIA=""
IS_PRE_SIGNED=false

# Env vars available when this script runs:
#   FILE_SOURCE     full rclone source path     e.g. "nextcloud:path/to/file.txt"
#   FILE_KEY        path after "remote:"        e.g. "path/to/file.txt"
#   FILE_ACTION     "created" or "removed"
#   FILE_PATH       absolute local temp path    empty when FILE_ACTION is "removed"
#   PRE_SIGNED_URL  signed URL                  set when IS_PRE_SIGNED=true, otherwise empty
#   FILE_MATCH_REASON  why the criteria gate passed  empty when CRITERIA is unset
set -euo pipefail

if [ "$FILE_ACTION" = "removed" ]; then
    echo "Delete event for $FILE_KEY — nothing to process."
    exit 0
fi

echo "Processing: $FILE_PATH"
echo "From:       $FILE_SOURCE"
echo "--- file contents ---"
cat "$FILE_PATH"
echo "--- end ---"
