#!/usr/bin/env bash
# Keep the version of the migration that just landed in applied/, so reconcile
# can tell when it changes and implement can diff against it. Runs before
# commit, so the copy lands in the same commit as the work.
set -euo pipefail
d="${DECREE_PROJECT_ROOT}/.decree"

f="${DECREE_DATA_SPEC:-}"
[ -n "${f}" ] || f=$(sed -n '2,/^---$/s/^migration: //p' "${DECREE_MESSAGE}" | head -n 1)
[ -n "${f}" ] || exit 0            # an ordinary inbox message: nothing to record
mkdir -p "${d}/applied"
cp "${d}/migrations/${f}" "${d}/applied/${f}"
echo "recorded applied/${f}"
