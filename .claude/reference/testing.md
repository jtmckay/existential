# Testing

Entry point: `./existential.sh test [lint|secrets|guards|harness|selfcheck|unit|integration|services]`
(bare `test` runs them all).

`src/test/` splits into `unit/` (no live services), `integration/` (live creds/containers),
`e2e/` (full-stack harness). Per-service tests live with the service as `exist.test.sh`.

## `exist.test.sh` (the service test convention)

Every service ships one. It validates the service from its own perspective (container running,
port listening, API smoke, env vars, deps reachable) and prints copy-pasteable remediation on
failure.

- **Read-only.** No stacking state; prefer pure observation. Unavoidable writes clean up in a
  verified `trap`.
- **Service-scoped** — flag missing deps, don't recurse.
- **Exit non-zero on failure.**
- **Skip cleanly when disabled** (`EXIST_IS_<CAT>_<SLUG>` false → exit 0).
- In sidecar context (`DECREE_SIDECAR=true`), `skip_if_disabled` and `probe_caddy` are no-ops.
- Suggested output: `[<slug>] <check>  OK|FAIL` with `observed:`/`fix:` lines.

It is also the sidecar health gate: the sidecar retries until this passes before the service is
considered healthy.

## Container-state gate

`src/test/integration/container-health.sh`. Adhoc has no docker socket, so per-service tests
can't see crash-looping/exited/unhealthy containers or network-less daemons. This host-side gate
asserts every container is `running`, not restart-looping, not `unhealthy`. Wired into
`./existential.sh test` (before the adhoc run-all) and `e2e.sh` (after `up -d --build`, fails
the quest on trip). e2e always uses `--build` so it never tests a stale image.

## Every test mechanism has an opposite

A test silently swallowing a failure is worse than no test. The opposites (all on the **host**,
need git/bash, no adhoc; part of `test` (all) and run early in `pre-push`):

- **`no-tracked-secrets.sh`** (`test secrets`) — asserts this public repo tracks no rendered
  secrets.
- **`guard-selftest.sh`** (`test guards`) — plants secret-shaped fixtures in throwaway repos and
  asserts `pre-commit` **and** `no-tracked-secrets.sh` actually trip (incl. the `*.exist.*` /
  `*.example` exemptions). New secret-guard logic ⇒ add a fixture here.
- **`harness-selftest.sh`** (`test harness`) — proves the *plumbing* surfaces failures:
  `run-all.sh` fails+names a failing suite, and `container-health.sh` (driven by a fake
  `docker`) trips on a bad container.
- **`test selfcheck`** (adhoc) — runs every `unit/test-*.sh` with `TEST_SELFCHECK=1`, which
  fires a one-line canary (`[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail …`) each suite carries
  just before its tally; asserts each suite then exits non-zero. **Every unit suite must carry
  that canary.**
- **`unit/test-validators.sh`** — opposite-tests the TS validators: builds violating fixture
  trees, asserts `validate-conventions`/`check-drift` exit non-zero (and pass on a clean tree).

## Shell lint

`./existential.sh test lint` → `src/test/lint-shell.sh`. Runs shellcheck at `-S warning` over
every tracked `*.sh` plus `.githooks/*` (graveyard excluded), in a throwaway
`koalaman/shellcheck-alpine` container pinned by tag **and** digest. Shellcheck is in neither
the host nor the adhoc image, and baking it into the decree image would force an image rebuild
on everyone for a developer-only tool — so this follows the same throwaway-container pattern as
the Go tests below.

It carries its own opposite: a canary with a deliberate SC2154 must be flagged first. A
shellcheck that silently isn't running (wrong entrypoint, changed flag, image swap) otherwise
reads as a clean pass — the exact rot the rest of this file targets.

Findings shellcheck structurally cannot resolve — decree injects `$message_file`, `$PATTERN`
and friends that no script assigns; several routines `source` a path computed at runtime —
carry a **targeted inline** `# shellcheck disable=SCxxxx  # <why>` at the site. Don't loosen
the gate globally or add blanket excludes: the same smell is a real bug somewhere else. It
found one the day it was wired up (env assignments prefixed to a command substitution instead
of the command inside it, so `ocr.ts` never received `FILE_PATH`).

Wired into `test` (all) and `pre-push`, grouped with the Docker-needing gates rather than the
Docker-free self-tests.

## Go services

Go services carry their own `go test` suite (e.g. `services/decree/webhook/main_test.go`). Adhoc
has no Go toolchain, so they are **not** part of `./existential.sh test` — run them from the
service dir, or in a container:

```bash
docker run --rm -v "$PWD":/src -w /src golang:1.26.5-alpine3.23 go test ./...
```

## Git hooks

`.githooks/` is auto-installed via `core.hooksPath=.githooks` on `default`/`quest`.

- **`pre-commit`** blocks secrets from entering the public repo — lean/fast, the one
  irreversible failure.
- **`pre-push`** runs the host-side opposites first (`test guards`, `test harness` — cheap, no
  Docker, fail fast) then `test unit`, `test selfcheck`, and `validate conventions` (heavier,
  needs Docker — gated once per push, not per commit).

Bypass either with `--no-verify`.
