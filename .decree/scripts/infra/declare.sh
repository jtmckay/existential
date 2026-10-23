#!/usr/bin/env bash
# infra's declare: Claude changes lib/infra/requirements to meet the message, and
# installs nothing; apply does. If the change needs a choice the message does not make,
# it writes the question to STOP instead of guessing; the run fails until a person
# answers it in plan.md, deletes STOP and runs `decree process --retry`.
set -euo pipefail
. "${DECREE_LIB}/ai.sh"

infra="${DECREE_LIB}/infra"
plan="${DECREE_RUN_DIR}/plan.md"
stop="${DECREE_RUN_DIR}/STOP"
stopped() {
  [ -f "${stop}" ] || return 1
  cat "${stop}" >&2
  echo stop > "${DECREE_EVENT_FILE}"
}
stopped && exit 0

prompt="You maintain this project's environment. Read ${DECREE_MESSAGE}.
The environment is declared: ${infra}/requirements lists each resource the project
needs (kind, name, version, source), in order, and ${infra}/kinds/<kind>.sh says how
to check and install that kind. Read both, then change the lines of requirements to
meet the message. Put a line after the lines it relies on, and pin every version the
kind takes. Only if no kind fits, add one in ${infra}/kinds/, a check and an install
function like the others: it installs into the project, never with sudo, and a step
only a person can do (root, an account) prints the command and returns 1. A kind that
downloads a file checks it against the sha256 in its line's source (<url>#sha256=<hex>)
and fails on a mismatch; take the hash from what the project publishes (a SHA256SUMS
file, the release page), never by downloading the file and hashing it yourself.
Change nothing else. Do not run anything that installs; the next step does. You may
look at this host read-only to find what a line relies on, and declare that too.
If ${plan} exists, follow it. If the message needs a choice it does not make, do not
guess: write the question to ${stop} and stop.
Write scratch files only under ${DECREE_RUN_DIR}, never outside the project (not /tmp)."
echo "=== AI prompt (declare) ==="
echo "${prompt}"
ai "${prompt}"
stopped || true
