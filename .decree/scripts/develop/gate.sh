#!/usr/bin/env bash
# develop's gate: the repo's own pre-push hook, so the checks live in one place.
# Names `pass` or `fail`; a non-zero exit (docker missing) means they could not run.
set -euo pipefail
log="${DECREE_ROOT_RUN_DIR}/gate.log"

command -v docker >/dev/null || command -v podman >/dev/null || {
  echo "gate: neither docker nor podman on PATH; the checks cannot run" | tee "${log}" >&2
  exit 1
}

if bash .githooks/pre-push 2>&1 | tee "${log}"; then
  echo pass > "${DECREE_EVENT_FILE}"
else
  echo fail > "${DECREE_EVENT_FILE}"
fi
