#!/usr/bin/env bash
# immich — pre-startup init: guard installs that predate the storage move.
#
# immich used to mount two raw host paths out of its own .env:
#   UPLOAD_LOCATION=./volumes/immich_library
#   DB_DATA_LOCATION=./volumes_local/immich_postgres
# Both are now declared volumes (volumes/immich_data, volumes/immich_pg_data).
#
# Nothing moves data automatically. This is a photo library and a postgres data
# directory; a script that relocates either one unattended is a script that can
# lose them. So: detect the old layout, refuse to let the stack come up pointing
# at empty new directories, and print the two commands to run.
#
# Idempotent and silent once the old paths are gone, which is the normal case —
# a fresh install never had them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

_old_lib="${REPO_DIR}/volumes/immich_library"
_old_pg="${REPO_DIR}/volumes_local/immich_postgres"
_new_lib="${REPO_DIR}/volumes/immich_data"
_new_pg="${REPO_DIR}/volumes/immich_pg_data"

_has_content() { [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; }

# Explicit `if`, not `a && b && c=1`: under `set -e` a bare && chain whose test
# comes out false is a failing command, and the script would exit silently right
# where it is supposed to start talking.
_stale=0
if _has_content "$_old_lib" && ! _has_content "$_new_lib"; then _stale=1; fi
if _has_content "$_old_pg"  && ! _has_content "$_new_pg";  then _stale=1; fi
[ "$_stale" -eq 1 ] || exit 0

cat >&2 <<MSG
[immich] Storage moved, and this install still has data at the old paths.

  photo library:  ${_old_lib}
                  -> ${_new_lib}
  database:       ${_old_pg}
                  -> ${_new_pg}

Both are now declared volumes, so the stack would come up pointing at empty
directories and immich would look wiped. Nothing has been changed.

With the stack down (docker compose down), move them. generate-compose.ts has
already created the new directories empty, so remove those first — otherwise mv
puts the old directory INSIDE the new one instead of becoming it:

  rmdir "${_new_lib}" "${_new_pg}"
  mv "${_old_lib}" "${_new_lib}"
  mv "${_old_pg}"  "${_new_pg}"
  rmdir "${REPO_DIR}/volumes_local" 2>/dev/null || true

Then run ./existential.sh again.
MSG
exit 1
