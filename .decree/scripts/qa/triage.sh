#!/usr/bin/env bash
# qa's triage: Claude sorts each failure into a real bug, a wrong test or acceptable
# behaviour. A bug's tests are marked expected to fail and get one report per root cause in
# bugs/; wrong tests are rewritten; acceptable ones are removed. The chaos suite must then
# pass, or the step fails. A failure the docs do not settle is a question in STOP; the run
# fails until a person answers it in plan.md, deletes STOP and runs `decree process --retry`.
set -euo pipefail
. "${DECREE_LIB}/ai.sh"
. "${DECREE_LIB}/qa/qa.sh"

bugs="${DECREE_RUN_DIR}/bugs"
plan="${DECREE_RUN_DIR}/plan.md"
stop="${DECREE_RUN_DIR}/STOP"
stopped() {
  [ -f "${stop}" ] || return 1
  cat "${stop}" >&2
  echo stop > "${DECREE_EVENT_FILE}"
}
stopped && exit 0
mkdir -p "${bugs}"
qa_guard

prompt="You are QA triage. Read ${DECREE_RUN_DIR}/chaos.log, the project's docs,
${DECREE_LIB}/qa/invariants.md, and ${plan} if it exists. For each failing test in
${QA_DIR}/, decide:
- Real bug: the project breaks an invariant or its docs. Mark the test expected to fail,
  with the framework's strict marker, so the suite passes now and fails once the bug is
  fixed (Python @unittest.expectedFailure or pytest xfail(strict=True), Playwright
  test.fail(), Jest test.failing, Rust #[should_panic]).
- Wrong test: it asserts something the docs do not require, or no correct code could pass
  it. Rewrite it to check the invariant, or delete it.
- Acceptable behaviour: delete the test.
- Unclear: the docs and invariants do not say. Write the question to ${stop} and stop.
Then group the real bugs by root cause: tests that fail for the same reason are one bug.
For each root cause write ${bugs}/<short-slug>.md for the developer: a title line naming
the broken behaviour; '## Overview': the invariant broken, every test it covers (file and
name), the wrench, and what happened (the error from chaos.log); '## Outcome': the expected
behaviour, as the invariant and the docs state it; '## Constraints': the tests' assertions
do not change; '## Acceptance Criteria': Given those tests, When the chaos suite runs
(${QA_RUN}), Then they pass with their expected-failure marker removed and their
assertions unchanged. State what is broken and what is expected, never a fix: name no
code, file or function to change and no way to change it.
Write one line per test to ${DECREE_RUN_DIR}/triage.md: test, verdict, root cause, why.
Change only files in ${QA_DIR}/ and ${DECREE_RUN_DIR}/. Do not run the tests.
Write scratch files only under ${DECREE_RUN_DIR}, never outside the project (not /tmp)."
echo "=== AI prompt (triage) ==="
echo "${prompt}"
ai "${prompt}"
stopped && exit 0
qa_check
if ! bash -c "${QA_RUN}" > "${DECREE_RUN_DIR}/chaos-after.log" 2>&1; then
  tail -n 20 "${DECREE_RUN_DIR}/chaos-after.log" >&2
  echo "qa: the chaos suite still fails; every failure must be marked, rewritten or removed" >&2
  exit 1
fi
