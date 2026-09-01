---
routine: triage
e2e_check: 00-services
requires: EXIST_IS_SERVICES_DECREE
TRIAGE_ALWAYS: "true"
TRIAGE_STRICT: "true"
TRIAGE_NOTIFY: "false"
TRIAGE_REPO: /repo
TRIAGE_STATE: /data/triage/e2e-state.env
---

Run every enabled service's own `exist.test.sh` and fail if any of them is
broken.

This is the whole per-service tier of e2e, as one message. It used to be a
separate `run-all.sh` invocation in the adhoc container, wired up with
`E2E_MODE=1` and a colon-separated `E2E_SERVICE_PATHS` list that e2e.sh built
from the quest's `services:` block. None of that was buying anything: triage
already runs every *enabled* service's test off the read-only `/repo` mount, and
under e2e the enabled set IS the quest's set — the fixture `.env.shared` starts
with everything off and e2e turns on exactly what the quest asks for.

`TRIAGE_ALWAYS` because the backoff exists to stop a long-lived daemon from
re-checking a healthy stack every five minutes, and this stack lives for one
run. `TRIAGE_STATE` is redirected so the e2e run cannot inherit or clobber the
green streak of a real install sharing the volume. `TRIAGE_NOTIFY` off because
nobody asked to be paged by a test.

`TRIAGE_STRICT` is the one that matters: triage normally exits 0 even with
services down, so that decree does not treat a true report of bad news as a
failed routine. Here the exit code is the verdict, so it exits non-zero and the
message dead-letters — which is exactly how e2e learns a service is broken.

The full per-service report lands in this run's `status.md`, next to
`routine.log`, and both are copied into `e2e-out/`.
