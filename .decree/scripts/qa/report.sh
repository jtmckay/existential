#!/usr/bin/env bash
# qa's report: one develop message per bug report in bugs/. Safe to re-run: a report
# already queued is listed in emitted.txt.
set -euo pipefail
emitted="${DECREE_RUN_DIR}/emitted.txt"
touch "${emitted}"
shopt -s nullglob
for bug in "${DECREE_RUN_DIR}"/bugs/*.md; do
  grep -qxF "${bug}" "${emitted}" && continue
  id=$("${DECREE}" emit --machine develop < "${bug}")
  echo "${bug}" >> "${emitted}"
  echo "queued ${id}: $(head -n 1 "${bug}")"
done
