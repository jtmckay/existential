#!/usr/bin/env bash
# qa's run: the chaos suite, into chaos.log. A failing test is a finding, so this exits 0
# either way; only a suite that could not start at all (command not found) is an error.
set -uo pipefail
. "${DECREE_LIB}/qa/qa.sh"
bash -c "${QA_RUN}" 2>&1 | tee "${DECREE_RUN_DIR}/chaos.log"
status=${PIPESTATUS[0]}
if [ "${status}" -ge 126 ]; then
  echo "qa: the chaos suite could not run (exit ${status}): ${QA_RUN}" >&2
  exit 1
fi
exit 0
