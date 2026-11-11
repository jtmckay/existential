---
machine: plugin
automation: file_processor
needs:
  - agent_task
  - model
  - router
chart:
  description: Download one file, put it to the processor's CRITERIA if it has any, then run the processor on it.
  data:
    rclone_path: {type: string, default: ""}
    processor: {type: string, default: ""}
    file_action: {type: string, enum: [created, removed], default: created}
    is_pre_signed: {type: bool, default: false}
    criteria: {type: string, default: ""}
  initial: process
  states:
    process:
      # A criteria gate with no verdict (the gateway down or slow) fails rather
      # than drop the file; three tries ride out a restart.
      invoke:
        script: {name: file_processor, attempts: 3}
      transitions: {done: done}
      # A processor may hand its file to an agent (file-processors.example/agent-handoff.sh).
      emits: [agent_task, router]
    done: {final: true}
    failed: {final: true}
scripts:
  file_processor: |
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
        # shellcheck source=../../lib/model.sh
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
lib:
  file-processors.example/example.sh: |
    #!/usr/bin/env bash
    # shellcheck disable=SC2034  # PATTERN, CRITERIA and IS_PRE_SIGNED are this file's
    # contract with file-router and file-processor, which read them out of the source
    # rather than by sourcing it. Nothing here consumes them.
    # Example file processor — copy/rename this file to add a new type.
    #
    # A processor declares up to two tests, and a file must pass both to reach the
    # body of the script:
    #
    # PATTERN (required) is matched against FILE_SOURCE, the full rclone path:
    #   "<rclone_src>:<path in Nextcloud>"  e.g. "nextcloud:workspace/2024/img.jpg"
    # It is a plain bash regex, evaluated by file-router. Cheap and mechanical.
    # A payload does not say file or folder, so anchor on an extension where you can.
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

    # Assert before you work. A processor that reports success over a file that
    # never downloaded is worse than one that fails: the run goes green and the
    # broken half of the chain — the remote, the prefix, or the key — stays hidden.
    # Exiting non-zero here dead-letters the message, which is how you find out.
    [ -s "$FILE_PATH" ] || { echo "Empty or missing: $FILE_PATH" >&2; exit 1; }

    echo "--- file contents ---"
    cat "$FILE_PATH"
    echo "--- end ---"
---
# file_processor

Download one file, put it to the processor's CRITERIA if it has any, then run the processor on it.

It needs, on the stack that installs it:

- $DECREE_LIB/file-processors/
- $DECREE_LIB/model.sh
