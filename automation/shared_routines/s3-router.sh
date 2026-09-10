#!/usr/bin/env bash
# S3 Router
#
# Receives SeaweedFS filer webhook events, matches the full FILE_SOURCE path
# against every processor in lib/file-processors/, and enqueues one file-processor
# message per match. The file is downloaded per-processor — no shared state.
#
# FILE_SOURCE is "<rclone_src>:<rclone_prefix><object-key>" — the event's S3
# BUCKET is parsed but deliberately discarded. The path has to be valid for the
# rclone remote, and in the default topology the bucket is a nextcloud external
# mount whose nextcloud-side path is the prefix. Talking to the object store
# directly over an s3 remote instead? Set rclone_prefix to the bucket name.
#
# Matching here is mechanical and cheap: PATTERN against the path, nothing else.
# A processor may also declare a CRITERIA= line — a natural-language test of the
# file's CONTENT — which is carried through to file-processor and evaluated
# there, after the download. Splitting it that way means the expensive half only
# runs for files that already passed the cheap half.
#
# The event shape is SeaweedFS's filer webhook (nas/seaweedfs/notification.toml),
# NOT S3 bucket notifications — SeaweedFS does not implement
# PutBucketNotificationConfiguration at all. Two consequences:
#
#   - `key` is a FILER path, "/buckets/<bucket>/<object key>", so the /buckets/
#     prefix is stripped before the bucket is split off.
#   - DIRECTORIES generate events too. minIO had no directory concept and never
#     did this. An unfiltered directory event makes file-processor try to
#     download a folder, so is_directory entries are dropped below. The field is
#     OMITTED rather than false for files, so test for true, not for presence.
#
# Example webhook trigger (fired by /s3 endpoint):
#
#   ---
#   routine: s3-router
#   rclone_src: nextcloud
#   rclone_prefix: S3
#   ---
#   {"event_type":"create","key":"/buckets/nextcloud/workspace/file.pdf","message":{...}}
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v jq >/dev/null 2>&1 || precheck_fail "s3-router" "jq not found"
    precheck_pass "s3-router"
    exit 0
fi

rclone_src="${rclone_src:-nextcloud}"
rclone_prefix="${rclone_prefix:-}"

# Parse the event
_json=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "$message_file" | sed '/./,$!d')

if [ -z "$_json" ]; then
    echo "Empty message body, nothing to route."
    exit 0
fi

_event_type=$(echo "$_json" | jq -r '.event_type // empty')
_key=$(echo "$_json"        | jq -r '.key        // empty')

if [ -z "$_event_type" ] || [ -z "$_key" ]; then
    echo "Could not parse event_type or key — verify seaweedfs is sending filer webhook events."
    echo "Payload: $_json"
    exit 1
fi

# Directories are not files. See the header.
if [ "$(echo "$_json" | jq -r '.message.new_entry.is_directory // false')" = "true" ] \
   || [ "$(echo "$_json" | jq -r '.message.old_entry.is_directory // false')" = "true" ]; then
    echo "Directory event ($_event_type $_key) — skipping."
    exit 0
fi

# "/buckets/nextcloud/workspace/f.pdf" -> "nextcloud/workspace/f.pdf"
_strip_buckets() { echo "${1#/buckets/}"; }

# Build the (action, object-key) pairs this event produces. Every event yields
# exactly one pair except a rename, which yields two.
#
# Translate the filer event to the same clean action strings minIO's router
# emitted, so no processor had to change:
#   create/update -> created   (minIO: ObjectCreated, fired on PUT and on overwrite)
#   delete        -> removed   (minIO: ObjectRemoved)
_pairs=()
case "$_event_type" in
    create|update)
        _pairs+=("created|$(_strip_buckets "$_key")")
        ;;
    delete)
        _pairs+=("removed|$(_strip_buckets "$_key")")
        ;;
    rename)
        # Nextcloud's files_external S3 driver implements rename as copy+delete, so
        # in the default topology this branch never fires — a rename arrives as an
        # independent create and delete, exactly as it did under minIO. It fires
        # only for filer-level moves: seaweedfs' own WebDAV/SFTP, a FUSE mount, or
        # the filer API. Handled anyway so pointing rclone at those is safe.
        #
        # `key` is the path BEFORE the move; the destination is new_parent_path
        # plus the new entry's name (the same fields an update event carries).
        _new_parent=$(echo "$_json" | jq -r '.message.new_parent_path // empty')
        _new_name=$(echo "$_json"   | jq -r '.message.new_entry.name  // empty')
        _pairs+=("removed|$(_strip_buckets "$_key")")
        if [ -n "$_new_parent" ] && [ -n "$_new_name" ]; then
            _pairs+=("created|$(_strip_buckets "${_new_parent%/}/${_new_name}")")
        else
            echo "Rename event without a usable destination — only the removal was routed."
        fi
        ;;
    *)
        echo "Unhandled event type '$_event_type' — skipping."
        exit 0
        ;;
esac

_processors_dir="$(dirname "${BASH_SOURCE[0]}")/../lib/file-processors"
_matched=0

for _pair in "${_pairs[@]}"; do
    _file_action="${_pair%%|*}"
    _bucket_and_key="${_pair#*|}"
    _object_key="${_bucket_and_key#*/}"
    _prefix="${rclone_prefix:+${rclone_prefix%/}/}"
    _file_source="${rclone_src}:${_prefix}${_object_key}"

    echo "Event:  $_event_type → $_file_action"
    echo "Source: $_file_source"

    # Find all matching processors and enqueue a file-processor message for each
    for _processor in "$_processors_dir"/*.sh; do
        [ -f "$_processor" ] || continue
        _raw=$(grep -m1 '^PATTERN=' "$_processor" || true)
        _pattern=$(echo "$_raw" | sed "s/^PATTERN=[\"']\(.*\)[\"']$/\1/")
        [ -z "$_pattern" ] && continue

        if [[ "$_file_source" =~ $_pattern ]]; then
            _processor_name=$(basename "$_processor" .sh)
            # decree reads the outbox but never creates it, so every routine that
            # queues a message has to. This router was the one that did not, and it
            # failed on the first event a fresh install ever routed.
            _outbox_dir="${OUTBOX_DIR:-/work/.decree/outbox}"
            mkdir -p "$_outbox_dir"
            # _matched is in the filename because a rename enqueues the same
            # processor twice (removed, then created) and the two must not collide.
            _outbox_file="${_outbox_dir}/${message_id}-${_matched}-${_processor_name}.md"

            _raw_ref=$(grep -m1 '^IS_PRE_SIGNED=' "$_processor" || true)
            _is_pre_signed=$(echo "$_raw_ref" | sed "s/^IS_PRE_SIGNED=[\"']\?\([^\"']*\)[\"']\?$/\1/")

            # Optional natural-language gate, evaluated by file-processor once the
            # content is actually on disk — the path is all we have here. Quoted
            # through jq because criteria are prose: colons and quotes are normal in
            # them — as they are in rclone_path, which carries an S3 object key and
            # so is whatever the user named their file. "Report: Q3.pdf" produces a
            # ": " in the value; unquoted, that message is invalid YAML and decree
            # re-runs it forever without ever writing run.json. Only processor,
            # file_action and is_pre_signed below are genuinely mechanical.
            _raw_crit=$(grep -m1 '^CRITERIA=' "$_processor" || true)
            _criteria=$(echo "$_raw_crit" | sed "s/^CRITERIA=[\"']\(.*\)[\"']$/\1/")

            # subroutine duplicates processor on purpose: processor is file-processor's
            # own dispatch input, subroutine is the generic "which sub-thing did this
            # run actually do" convention afterEach.sh surfaces to Grafana. Same value
            # here, but they answer different questions and a future routine's
            # subroutine won't always equal some other field it also happens to set.

            cat > "$_outbox_file" << EOF
---
routine: file-processor
rclone_path: $(jq -rn --arg v "${_file_source}" '$v|@json')
processor: ${_processor_name}
subroutine: ${_processor_name}
file_action: ${_file_action}
is_pre_signed: ${_is_pre_signed:-false}
criteria: $(jq -rn --arg v "${_criteria}" '$v|@json')
---
EOF
            echo "Queued: $_processor_name"
            _matched=$((_matched + 1))
        fi
    done
done

if [ "$_matched" -eq 0 ]; then
    echo "No processors matched."
else
    echo "Routed to $_matched processor(s)."
fi
