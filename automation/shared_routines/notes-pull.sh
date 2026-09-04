#!/usr/bin/env bash
# Notes Pull
#
# Opt-in: rsync-pulls notes (e.g. an Obsidian vault) from an external host
# into workspace/notes/ (or wherever NOTES_PULL_SUBDIR points), so a vault
# that lives somewhere else becomes part of the workspace/ knowledgebase —
# indexed by OpenViking, bisynced to MinIO, and (if the live workspace-pull
# processor and webhook subscription are active) event-triggering, exactly
# like anything else under workspace/.
#
# Why rsync over SSH and not another rclone remote: the source is assumed to
# be a plain filesystem reachable over SSH (a NAS, a synced folder on another
# box) rather than an S3-shaped store — rsync is the standard tool for that,
# and needs no bucket/credential setup on the source side.
#
# One-way, and deliberately not --delete by default: this PULLS A COPY in, it
# does not mirror. A source that goes offline, gets unmounted, or is
# temporarily empty should never be able to wipe local notes as a side
# effect — opt into NOTES_PULL_DELETE=true only once you trust the source's
# uptime as much as you trust decree's cron.
#
# SSH key: put a private key at automation/secrets/notes-pull/id_ed25519 (any
# name — set NOTES_PULL_SSH_KEY to match) and its public half in the source
# host's authorized_keys. automation/secrets/ is gitignored and mounted into
# this daemon at /secrets, the same place rclone's config lives.
#
# A source without a "host:" prefix (a local path, or a share already mounted
# into this container) skips SSH entirely — rsync copies it directly.
#
# Copy to services/automation/backup/cron/ and set NOTES_PULL_SOURCE (and
# NOTES_PULL_SSH_KEY, if the key isn't at the default path) to activate — see
# cron.example/notes-pull.md.
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
NOTES_PULL_SOURCE="${NOTES_PULL_SOURCE:-}"
NOTES_PULL_SUBDIR="${NOTES_PULL_SUBDIR:-notes}"
NOTES_PULL_SSH_KEY="${NOTES_PULL_SSH_KEY:-/secrets/notes-pull/id_ed25519}"
NOTES_PULL_SSH_PORT="${NOTES_PULL_SSH_PORT:-22}"
NOTES_PULL_DELETE="${NOTES_PULL_DELETE:-false}"
NOTES_PULL_EXTRA_ARGS="${NOTES_PULL_EXTRA_ARGS:-}"

_is_remote_source() {
    # user@host:/path or host:/path — a bare local path never has a ':'
    # before its first '/', and rsync's own "host:" detection works the
    # same way (a Windows-style "C:/" drive letter is not a use case here).
    [[ "${NOTES_PULL_SOURCE}" == *:* && "${NOTES_PULL_SOURCE}" != /* ]]
}

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v rsync >/dev/null 2>&1 || { echo "rsync not found" >&2; exit 1; }
    [[ -d "${WORKSPACE_DIR}" ]]      || { echo "${WORKSPACE_DIR} is not a directory — is ../../workspace mounted into decree-backup?" >&2; exit 1; }
    [[ -n "${NOTES_PULL_SOURCE}" ]]  || { echo "NOTES_PULL_SOURCE not set — see cron.example/notes-pull.md" >&2; exit 1; }
    if _is_remote_source; then
        command -v ssh >/dev/null 2>&1  || { echo "ssh not found (NOTES_PULL_SOURCE looks like a remote spec)" >&2; exit 1; }
        [[ -f "${NOTES_PULL_SSH_KEY}" ]] || { echo "${NOTES_PULL_SSH_KEY} not found — see cron.example/notes-pull.md" >&2; exit 1; }
    fi
    exit 0
fi

_target="${WORKSPACE_DIR}/${NOTES_PULL_SUBDIR}"
mkdir -p "${_target}"

_args=(-a --human-readable --stats)
[[ "${NOTES_PULL_DELETE}" == "true" ]] && _args+=(--delete)

if _is_remote_source; then
    _args+=(-e "ssh -i ${NOTES_PULL_SSH_KEY} -p ${NOTES_PULL_SSH_PORT} -o StrictHostKeyChecking=accept-new -o BatchMode=yes")
fi

if [[ -n "${NOTES_PULL_EXTRA_ARGS}" ]]; then
    # shellcheck disable=SC2206
    _extra=(${NOTES_PULL_EXTRA_ARGS})
    _args+=("${_extra[@]}")
fi

echo "Pulling ${NOTES_PULL_SOURCE} -> ${_target} (delete=${NOTES_PULL_DELETE})"
rsync "${_args[@]}" "${NOTES_PULL_SOURCE%/}/" "${_target%/}/"
echo "Pull complete."
