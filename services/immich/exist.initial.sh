#!/usr/bin/env bash
# immich — pre-startup init: create the two host directories immich mounts.
#
# Unlike every other service, immich does not name its storage in
# `x-exist-volumes:` — it mounts two raw host paths straight from its own
# `.env` (UPLOAD_LOCATION, DB_DATA_LOCATION), because that file is
# `convention-exempt: upstream-env` and the keys have to keep their upstream
# names. generate-compose.ts only creates the dirs for volumes it can see by
# name, so it never creates these two.
#
# Docker then creates whatever is missing at `up` time — as ROOT. immich-postgres
# runs as ${EXIST_PUID}, so its very first initdb dies with
#   initdb: error: could not change permissions of directory
#           "/var/lib/postgresql/data": Operation not permitted
# and immich-server follows it down with ENOTFOUND immich-postgres. Creating the
# dirs here, from the host user that runs ./existential.sh, is the whole fix.
#
# Idempotent, no sentinels: mkdir -p on a dir that exists is a no-op, and an
# existing dir's ownership is never touched — a library already sitting on NFS
# under some other uid must stay exactly as it is.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
ENV_FILE="${SCRIPT_DIR}/.env"

[ -f "$ENV_FILE" ] || exit 0   # not rendered yet; nothing to place

_get() { grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2-; }

for _key in UPLOAD_LOCATION DB_DATA_LOCATION; do
    _path="$(_get "$_key")"
    [ -n "$_path" ] || continue
    # Paths are relative to the compose project root (the repo), not to this dir.
    case "$_path" in
        /*) _abs="$_path" ;;
        *)  _abs="${REPO_DIR}/${_path#./}" ;;
    esac
    if [ ! -d "$_abs" ]; then
        mkdir -p "$_abs"
        echo "[immich] created ${_key} → ${_abs}"
    fi
done
