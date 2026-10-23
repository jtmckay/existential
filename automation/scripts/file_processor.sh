#!/usr/bin/env bash
# File Processor
#
# Downloads a file from any rclone remote, passes it to the named processor
# in lib/file-processors/, then explicitly deletes the temp file.
# Not object-store-specific — works with any rclone path.
#
# Emitted by file_router; not typically triggered directly.
#
# When `criteria` is set, the downloaded content is put to the model before the
# processor runs, and the processor is skipped unless it matches. file_router
# fills this in from the processor's own CRITERIA= line; an empty value means
# the path match was the whole test.
set -euo pipefail

rclone_path="$DECREE_DATA_RCLONE_PATH"
processor="$DECREE_DATA_PROCESSOR"
file_action="$DECREE_DATA_FILE_ACTION"
is_pre_signed="$DECREE_DATA_IS_PRE_SIGNED"
criteria="$DECREE_DATA_CRITERIA"
PROCESSOR_MAX_CHARS="${PROCESSOR_MAX_CHARS:-6000}"

if [ -z "$rclone_path" ]; then
    echo "rclone_path is required."
    exit 1
fi
if [ -z "$processor" ]; then
    echo "processor is required."
    exit 1
fi
# `processor` is a param, and params are attacker-shaped input — they reach
# decree from webhooks, from email, and from agents. It is interpolated into a
# path that is then `bash`ed a few lines down, so a value like
# `../../../../workspace/evil` executes a file a confined agent can write.
if ! printf '%s' "$processor" | grep -qE '^[A-Za-z0-9_-]+$'; then
    echo "Invalid processor name: must match [A-Za-z0-9_-]+"
    exit 1
fi

_processor_script="${DECREE_LIB}/file-processors/${processor}.sh"
if [ ! -f "$_processor_script" ]; then
    echo "Processor not found: $_processor_script"
    exit 1
fi

# Derive a clean key from the rclone path (strip "remote:" prefix)
_file_key="${rclone_path#*:}"

export FILE_SOURCE="$rclone_path"
export FILE_KEY="$_file_key"
export FILE_ACTION="$file_action"
export FILE_PATH=""
export PRE_SIGNED_URL=""

_tmpfile=""
trap '[ -n "$_tmpfile" ] && rm -f "$_tmpfile" && echo "Deleted: $_tmpfile"' EXIT

if [ "$file_action" = "created" ]; then
    if [ "$is_pre_signed" = "true" ]; then
        echo "Generating signed URL for $rclone_path"
        _signed_url=$(rclone link "$rclone_path" \
            --config /secrets/rclone/rclone.conf)
        export PRE_SIGNED_URL="$_signed_url"
        echo "Signed URL: $PRE_SIGNED_URL"
    else
        _filename=$(basename "$_file_key")
        _tmpfile=$(mktemp "${DECREE_RUN_DIR}/${_filename}.XXXXXX")

        echo "Downloading $rclone_path → $_tmpfile"
        rclone copyto "$rclone_path" "$_tmpfile" \
            --config /secrets/rclone/rclone.conf \
            --progress \
            --stats-one-line

        export FILE_PATH="$_tmpfile"
    fi
fi

# --- Criteria gate ---------------------------------------------------------
#
# Skipped for deletes (nothing to judge — a processor decides for itself what a
# removal means) and when the file was never downloaded, which is the case for
# IS_PRE_SIGNED processors. Those two hand off a URL or a bare key, so there is
# no content here to put to the model; a criteria-gated processor should be a
# text one.
if [ -n "$criteria" ] && [ "$file_action" = "created" ] && [ -n "$FILE_PATH" ]; then
    # shellcheck source=../lib/model.sh
    source "${DECREE_LIB}/model.sh"

    echo "Evaluating criteria: ${criteria}"
    _body="$(head -c "$PROCESSOR_MAX_CHARS" "$FILE_PATH")"
    _reason=""
    set +e
    _reason="$(model_gate "$criteria" "Path: ${FILE_KEY}

---
${_body}")"
    _verdict=$?
    set -e

    case "$_verdict" in
        0) echo "match: ${_reason}" ;;
        1) echo "skip (criteria): ${FILE_KEY} does not match — not running ${processor}."
           exit 0 ;;
        # No verdict at all: the model server is down or slow. Fail so decree retries
        # (the state's attempts) rather than silently dropping the file, which
        # would look exactly like a clean "no match".
        *) echo "No verdict from the model — failing so this is retried." >&2
           exit 1 ;;
    esac

    export FILE_MATCH_REASON="$_reason"
fi

echo "Running processor: $processor (action: $file_action)"
bash "$_processor_script"
