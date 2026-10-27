---
machine: triage
e2e_check: 00-services
requires: EXIST_IS_SERVICES_AUTOMATION EXIST_IS_SERVICES_AUTOMATION_BACKUP
params:
  TRIAGE_ALWAYS: true
  TRIAGE_STRICT: true
  TRIAGE_NOTIFY: false
  TRIAGE_STATE: /data/triage/e2e-state.env
---

Run every enabled service's own `exist.test.sh` and fail if any of them is broken.

**This is why checks are messages and not migrations.** As a migration it ran
during decree's boot, which is before anything slow has finished starting — it
failed hermes, appsmith, lowcoder, nocodb and nextcloud on four runs whose
containers the health gate then found perfectly healthy. Migrations are setup;
this is verification, and verification runs once the stack is up. e2e drops it
after the container-health gate for exactly that reason.

Without this, a unit with no migrations and no object store verifies *nothing*: Core
and a flow made only of services write no files, so without this check they bring
their containers up and report `0 of 0 checks` —
a fair verdict on a run that demonstrated nothing, and a useless one to ship.

`TRIAGE_ALWAYS` because the backoff exists to stop a long-lived daemon
re-checking a healthy stack every five minutes, and this stack lives for one run.
`TRIAGE_STATE` is redirected so an e2e run cannot inherit or clobber the green
streak of a real install sharing the volume. `TRIAGE_NOTIFY` off because nobody
asked to be paged by a test.

`TRIAGE_STRICT` is the one that matters: triage normally exits 0 even with
services down, so decree does not treat a true report of bad news as a failed
run. Here the exit code is the verdict.
