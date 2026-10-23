#!/usr/bin/env bash
# develop's implement: Claude implements the message in small steps, noting
# each in progress.md, so a retry continues where the last attempt stopped. If
# the message is unclear, it writes the question to STOP instead of guessing;
# the run fails until a person answers it in plan.md, deletes STOP and runs
# `decree process --retry`. Its notes live in the root run's folder
# ($DECREE_ROOT_RUN_DIR, the run's own unless it is a child run), so a child machine
# whose steps are develop's scripts shares them.
set -euo pipefail
. "${DECREE_LIB}/ai.sh"

progress="${DECREE_ROOT_RUN_DIR}/progress.md"
plan="${DECREE_ROOT_RUN_DIR}/plan.md"
stop="${DECREE_ROOT_RUN_DIR}/STOP"
stopped() {
  [ -f "${stop}" ] || return 1
  cat "${stop}" >&2
  echo stop > "${DECREE_EVENT_FILE}"
}
stopped && exit 0

# Migrations are declarative: the message is the desired state of its concern.
# On a reconcile re-run, applied/ holds the version that last landed.
previous=""
if [ -n "${DECREE_DATA_SPEC:-}" ] && [ -f "${DECREE_PROJECT_ROOT}/.decree/applied/${DECREE_DATA_SPEC}" ]; then
  previous="
This message landed before; the version that landed is
.decree/applied/${DECREE_DATA_SPEC}. Diff the two: make the repository match the
message as it is now, and undo whatever only the old version asked for."
fi

prompt="You are a senior engineer. Read ${DECREE_MESSAGE}: it declares the
state the repository must be in for one concern. Make the repository match it,
with tests. Parts may already be true; leave those alone.
Documentation (README.md, site/docs/, the homepage in site/src/) must describe the
repository as it is after your change: update what your change makes untrue, in this run.${previous}
Work in small steps, one requirement at a time, and keep the code building
between steps. After each step, append a line to ${progress}: what is done
and what is next. If ${progress} exists, an earlier attempt was cut short:
check the code against it and continue from there. If ${plan} exists, follow it.
If the message is ambiguous or conflicts with the code, do not guess: write
the question to ${stop} and stop.
Logs of earlier attempts (if any) are in ${DECREE_RUN_DIR}.
Write scratch files only under ${DECREE_RUN_DIR}, never outside the project (not /tmp)."
echo "=== AI prompt (implementation) ==="
echo "${prompt}"
ai "${prompt}"
stopped || true
