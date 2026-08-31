#!/usr/bin/env bash
# openviking-index-dir — index a local directory tree into OpenViking, and keep
# it in sync on every run.
#
# Why not a watched directory: OpenViking's HTTP server refuses host filesystem
# paths outright (server/local_input_guard.py — "HTTP server only accepts remote
# resource URLs or temp-uploaded files"), and its MCP endpoint applies the same
# guard. `POST /api/v1/resources` with a file:// path returns PERMISSION_DENIED
# on v0.3.24, so a watch registered from another container cannot work. The
# supported route for local content is the two-leg upload this does:
#   POST /api/v1/resources/temp_upload  → temp_file_id
#   POST /api/v1/resources              → { temp_file_id, to }
#
# Restart-safe by construction. Embedding a large directory takes far longer
# than the cron interval, so this run WILL be interrupted — by the next tick, by
# a container restart, by `docker compose up`. Two things make that cost one
# file rather than the whole directory:
#
#   * The manifest is an append-only log, fsync'd per file, last-line-wins. A
#     killed run leaves every file it already finished recorded, so the next run
#     resumes instead of re-uploading from the top. It is compacted only after a
#     full pass, and only in a way that is safe to interrupt.
#   * A lock means overlapping runs never stack. A tick that finds a run in
#     progress exits immediately rather than starting a second upload of the
#     same file. The lock lives on an fd, so a killed run releases it — there is
#     no stale lockfile to clear by hand.
#
# Env vars (set via cron frontmatter):
#   INDEX_DIR     directory to index, as seen inside the daemon (e.g. /workspace)
#   INDEX_PREFIX  viking:// destination prefix
#                   (default viking://resources/<basename of INDEX_DIR>)
#   INDEX_EXCLUDE optional extended-regex of relative paths to skip
#
# Env vars (passed through the decree container's compose env):
#   OPENVIKING_API_KEY  Bearer token for the OpenViking REST API
#   OPENVIKING_URL      defaults to http://openviking:1933
#   INDEX_STATE_DIR     manifest location (default /index-cache)
set -euo pipefail

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v curl      >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
    command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum not found" >&2; exit 1; }
    command -v flock     >/dev/null 2>&1 || { echo "flock not found" >&2; exit 1; }
    [[ -n "${INDEX_DIR:-}" ]]          || { echo "INDEX_DIR not set in frontmatter" >&2; exit 1; }
    [[ -d "${INDEX_DIR}" ]]            || { echo "INDEX_DIR ${INDEX_DIR} is not a directory" >&2; exit 1; }
    [[ -n "${OPENVIKING_API_KEY:-}" ]] || { echo "OPENVIKING_API_KEY not set" >&2; exit 1; }
    exit 0
fi

OPENVIKING_URL="${OPENVIKING_URL:-http://openviking:1933}"
INDEX_DIR="${INDEX_DIR%/}"
INDEX_PREFIX="${INDEX_PREFIX:-viking://resources/$(basename "${INDEX_DIR}")}"
INDEX_PREFIX="${INDEX_PREFIX%/}"
STATE_DIR="${INDEX_STATE_DIR:-/index-cache}"

# A ROOT key is not enough on its own: every tenant-scoped endpoint 400s with
# "ROOT requests to tenant-scoped APIs must include X-OpenViking-Account and
# X-OpenViking-User headers" unless both are sent.
AUTH=(-H "Authorization: Bearer ${OPENVIKING_API_KEY}"
      -H "X-OpenViking-Account: default"
      -H "X-OpenViking-User: default")

mkdir -p "${STATE_DIR}"
SLUG=$(printf '%s' "${INDEX_DIR}" | tr -c 'A-Za-z0-9' '_')
MANIFEST="${STATE_DIR}/${SLUG}.tsv"
LOCK="${STATE_DIR}/${SLUG}.lock"
touch "${MANIFEST}" "${LOCK}"

# One indexer per directory. A run that outlives the cron interval is normal on
# a first pass; the next tick should step aside, not pile on. Held on fd 9 for
# the life of this process, so a crash or `docker kill` frees it.
exec 9>"${LOCK}"
if ! flock -n 9; then
    echo "Another openviking-index-dir run is still working on ${INDEX_DIR} — skipping this tick."
    exit 0
fi

# Append-only, one line per completed file: "<sha256|-> <TAB> <relpath>". A '-'
# hash is a tombstone (removed from the index). Last line for a path wins, so a
# rewrite is an append and an interrupted run never leaves a half-written record.
_record() {
    printf '%s\t%s\n' "$1" "$2" >> "${MANIFEST}"
    # Without the flush, a container kill loses the tail of the log and the next
    # run re-uploads files that were already embedded.
    sync -f "${MANIFEST}" 2>/dev/null || sync
}

# Last-wins view of the log, as "<hash><TAB><relpath>", tombstones dropped.
_manifest_state() {
    [[ -s "${MANIFEST}" ]] || return 0
    tac "${MANIFEST}" | awk -F'\t' '!seen[$2]++' | awk -F'\t' '$1 != "-"'
}

# viking:// URIs are built by joining path segments, so a relative path has to be
# percent-encoded — a space or '#' in a filename otherwise produces a URI that
# resolves to something else on the next run, and the file re-uploads forever.
# '/' is deliberately left literal: it is the separator that mirrors the tree.
_encode_uri_path() {
    printf '%s' "$1" | od -An -tx1 -v | tr -s ' ' '\n' | grep -v '^$' | while read -r byte; do
        case "$byte" in
            2f|2d|2e|5f|7e|3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a])
                printf '%b' "\\x${byte}" ;;
            *)  printf '%%%s' "$(printf '%s' "$byte" | tr 'a-f' 'A-F')" ;;
        esac
    done
}

_remove_uri() {
    # 404 is success: the goal is "not present", and a manifest can outlive the
    # resource it names (deleted in the Studio, or the store was reset).
    local uri="$1" code
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 60 -X DELETE "${AUTH[@]}" \
        --get --data-urlencode "uri=${uri}" --data "recursive=true" \
        "${OPENVIKING_URL}/api/v1/fs" 2>/dev/null || echo "000")
    [[ "$code" == "200" || "$code" == "404" ]]
}

_upload() {
    local file="$1" uri="$2" tfid resp
    resp=$(curl -sS --max-time 300 -X POST "${AUTH[@]}" \
        -F "file=@${file}" "${OPENVIKING_URL}/api/v1/resources/temp_upload" 2>/dev/null || true)
    tfid=$(printf '%s' "$resp" | sed -n 's/.*"temp_file_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ -z "$tfid" ]]; then
        echo "  upload failed: ${resp:-no response}" >&2
        return 1
    fi
    # wait=false deliberately. The reply confirms the resource was accepted and
    # queued, which is the part this routine controls; embedding happens behind
    # it. Blocking on the queue instead ties every run to embedding health — when
    # the embed model is missing, OpenViking opens a circuit breaker and retries
    # forever, and a `wait` run sits there for its whole timeout PER FILE. That
    # turns one broken setting into an indexer that never finishes a pass.
    # openviking's exist.test.sh is what reports a broken embed model.
    resp=$(curl -sS --max-time 180 -X POST "${AUTH[@]}" \
        -H 'Content-Type: application/json' \
        -d "{\"temp_file_id\": \"${tfid}\", \"to\": \"${uri}\", \"create_parent\": true, \"wait\": false}" \
        "${OPENVIKING_URL}/api/v1/resources" 2>/dev/null || true)
    case "$resp" in
        *'"status":"ok"'*) return 0 ;;
        # An upload killed mid-flight leaves the destination locked server-side.
        # OpenViking flags it retryable and clears it on its own, so this is a
        # "not yet", not a failure — nothing is recorded, and the next run picks
        # the file up again.
        *'"conflict_type":"path_busy"'*) return 2 ;;
        *) echo "  add_resource failed: ${resp:-no response}" >&2; return 1 ;;
    esac
}

STATE=$(_manifest_state || true)
ADDED=0 UPDATED=0 UNCHANGED=0 REMOVED=0 BUSY=0 FAILED=0

while IFS= read -r -d '' file; do
    REL="${file#"${INDEX_DIR}"/}"
    if [[ -n "${INDEX_EXCLUDE:-}" ]] && [[ "$REL" =~ ${INDEX_EXCLUDE} ]]; then
        continue
    fi
    HASH=$(sha256sum "$file" | cut -d' ' -f1)
    PREV=$(printf '%s\n' "$STATE" | grep -F -m1 "	${REL}" | cut -f1 || true)
    URI="${INDEX_PREFIX}/$(_encode_uri_path "${REL}")"

    if [[ "$PREV" == "$HASH" ]]; then
        UNCHANGED=$((UNCHANGED + 1))
        continue
    fi

    if [[ -n "$PREV" ]]; then
        echo "Re-indexing ${REL}"
        # Replace rather than stack: without this the old copy stays searchable
        # alongside the new one and results contradict each other.
        _remove_uri "$URI" || echo "  could not remove previous ${URI} — adding anyway" >&2
    else
        echo "Indexing ${REL}"
    fi

    set +e
    _upload "$file" "$URI"
    RC=$?
    set -e
    case "$RC" in
        0)  _record "$HASH" "$REL"
            if [[ -n "$PREV" ]]; then UPDATED=$((UPDATED + 1)); else ADDED=$((ADDED + 1)); fi ;;
        2)  echo "  ${REL} is busy in OpenViking — retrying on the next run"
            BUSY=$((BUSY + 1)) ;;
        # Nothing recorded — the next run retries this file and only this file.
        *)  FAILED=$((FAILED + 1)) ;;
    esac
done < <(find "${INDEX_DIR}" -type f -not -path '*/.*' -print0 | sort -z)

# Anything the manifest still claims is indexed but is no longer on disk.
while IFS=$'\t' read -r _hash rel; do
    [[ -z "$rel" ]] && continue
    [[ -e "${INDEX_DIR}/${rel}" ]] && continue
    echo "Removing ${rel} (deleted on disk)"
    if _remove_uri "${INDEX_PREFIX}/$(_encode_uri_path "${rel}")"; then
        _record "-" "$rel"
        REMOVED=$((REMOVED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
done < <(printf '%s\n' "$STATE")

# Compact the log only after a clean full pass, and only via a rename — an
# interrupt here leaves the previous manifest intact rather than a truncated one.
if [[ "$FAILED" -eq 0 && "$BUSY" -eq 0 ]]; then
    COMPACT="${MANIFEST}.compact"
    if _manifest_state > "${COMPACT}" 2>/dev/null; then
        mv -f "${COMPACT}" "${MANIFEST}"
    else
        rm -f "${COMPACT}"
    fi
fi

echo "OpenViking index ${INDEX_DIR} → ${INDEX_PREFIX}: ${ADDED} added, ${UPDATED} updated, ${UNCHANGED} unchanged, ${REMOVED} removed, ${BUSY} busy, ${FAILED} failed."
# Busy is not a failure: the file is simply picked up next tick. Only a real
# error exits non-zero, so decree retries the run rather than dead-lettering it
# over a lock that clears itself.
[[ "$FAILED" -eq 0 ]]
