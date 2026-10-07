#!/usr/bin/env bash
# seaweedfs — pre-startup init: create the metadata subdirectories.
#
# weed does NOT create these itself. -master.dir and -admin.dataDir are checked for
# writability at boot and the process dies on a missing one:
#
#   F mini.go Check Meta Folder (-dir="/meta/master") Writable: no such file or directory
#
# generate-compose.ts creates volumes/<name> for every declared volume, but not
# subdirectories inside one — so these three are ours to make.
#
# They live under seaweedfs_meta_data (db: true) rather than seaweedfs_data
# (nfs: true) because all three are embedded databases and NFS corrupts those.
# See .claude/reference/volumes.md.
#
# Idempotent, no sentinel: mkdir -p on every run, silent once they exist. Runs as the
# invoking user, which is the same EXIST_PUID the container runs as — so the dirs are
# already owned by the process that has to write them.
#
# See .claude/reference/services.md for the convention.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
META_DIR="${REPO_ROOT}/volumes/seaweedfs_meta_data"

mkdir -p "${META_DIR}/master" "${META_DIR}/admin" "${META_DIR}/filer"
