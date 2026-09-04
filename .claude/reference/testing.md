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
- Inside the **backup** daemon (`DECREE_BACKUP=true`), `skip_if_disabled` and `probe_caddy` are
  no-ops. Not in `decree`: triage runs there against a mounted `/repo`, and the Caddy probe is
  what separates "service down" from "routing broken".
- Suggested output: `[<slug>] <check>  OK|FAIL` with `observed:`/`fix:` lines.

It is also what the health gates run: `triage` executes every enabled service's copy off the
`decree` daemon's read-only `/repo` mount every 5 minutes, and `migration-gate.sh` uses the same
idea to hold migrations back until their target service answers.

## End-to-end

`./existential.sh e2e [--all|<pattern>...|down]` → `src/test/e2e/e2e.sh`. Per selected quest:
copy the **working tree** into `.tmp-e2e-*` → copy
`src/test/fixtures/env.shared` over `.env.shared` and flip on the quest's `EXIST_IS_*` vars →
**stage checks** → render templates → `run_initials` (sourced from the clone's own
`existential.sh`, not a second copy) → `generate-compose.ts` → `up -d --build` → settle →
container-state gate → **wait for decree to finish migrating** → copy the evidence to
`e2e-out/` → tear down. Quests are selected by `e2e: true` frontmatter; `e2e: false` ones need
manual NAS/DNS/TLS setup and must carry an `e2e_skip:` reason (enforced by
`validate-conventions.ts`).

**The clone is the working tree, not `HEAD`** — `git ls-files --cached --others --exclude-standard`
(plus a `--deleted` subtraction, so an unstaged delete reads as deleted here too), piped through
`tar` so modes and symlinks survive: the scripts run by path (`existential.sh`, `.githooks/*`,
decree hooks, container `entrypoint:` targets) are dead without their `+x` bit. So uncommitted
work is what gets tested, and git's own ignore rules are what keeps `.env.shared`, rendered
`docker-compose.yml`s, `volumes/`, `workspace/`, `e2e-out/` and `archive/` out of the clone —
the same filter that keeps them out of a commit. One consequence: an untracked file that is *not*
gitignored now lands in the clone.

**A check is a markdown file in `src/test/e2e/checks/`** — a decree **message** naming a routine,
dropped into the clone's inbox *after* the container-health gate and run by the daemon.
Adding a check is adding a file. Full contract in that directory's `README.md`; the short version:

- `00-services.md` runs `triage` with `TRIAGE_STRICT=true` — the per-service tier. Without it a
  quest with no migrations and no MinIO verifies **nothing**: five of the eight copy only cron
  files (nightly/weekly backups, `clean-runs`, `gmail-sync`), none of which can fire inside a run
  that lives for minutes, so they reported `0 of 0 checks` and failed on that alone.
- A check with a sibling `.sh` gets it staged into the clone's `shared_routines/` and registered,
  so test code never lands in a user's `config.yml`. It runs **inside `decree`**: `mc`, `rclone`,
  `jq`, `yq`, `curl`, `tsx`, service credentials, `/repo` read-only, DNS to every container — but
  no Docker socket. Anything needing one stays on the host in `e2e.sh`.
- **Messages, not migrations, and dropped after the gate.** `decree process` stops at the first
  dead letter, so migrations would let one failure hide the rest. The reason that actually bit us
  is timing: migrations run during decree's **boot**, so a check written as one judges a stack
  that is still starting — it failed hermes, appsmith, lowcoder, nocodb and nextcloud on four
  quests the health gate then found healthy. Migrations are setup; checks are verification.
- decree runs **one message at a time**, and a check *is* that message — so a check can prove work
  was enqueued but can never wait for work it triggered. Push those assertions down (a probe
  processor that validates its own inputs); `decree process` drains the whole inbox before the
  daemon starts, so that queued work runs and is graded inside the same wait.

One run at a time: `e2e.sh` takes a machine-wide `flock` on `/tmp/exist-e2e.lock` before it
does anything, because its startup teardown reclaims *any* `.tmp-e2e-*` stack it finds — a second
run would delete the first one's containers mid-flight. `e2e down` takes the same lock. flock
frees on process death, so a crash leaves nothing stale.

**`e2e-out/<stamp>-<quest>/`** (gitignored) is the output directory: `results.md` (one row per
check), each run's `message.md`/`routine.log`/`run.json` copied verbatim, `dead/`, `stuck/`, and
`logs/` for any container the gate was unhappy about. It is written before teardown *and* from the
`cleanup` trap, so a crashed or interrupted run still leaves its evidence. `E2E_KEEP=1`
additionally leaves the stack standing for live poking; `./existential.sh e2e down` reclaims
containers, networks, volumes and work dirs from a crashed run.

Verdict: `run.json` with `exit_code: 0` passes; no `run.json`, a non-zero code, or a dead letter
fails. A quest also fails on the container-state gate, on decree never reaching its daemon phase
(its migrations never finished), and on producing **no** runs at all — a run that verified
nothing must not read green.

Its opposite lives in `harness-selftest.sh` (below): `collect_results` driven against a fabricated
`runs/` tree.

## Traps this harness has already fallen into

Each of these was tried, shipped, and reverted. They all look like simplifications.

- **Core is not a representative quest — verify a harness change against all of them.** Core is
  the only quest with a full migration set; five of the others copy *cron files only*. Twice a
  change was justified against a green Core and broke everything else: stripping the clone's crons
  left those five with nothing gradable at all (a guaranteed `0 of 0` = fail), and running checks
  as migrations passed Core only because `migration-gate.sh` holds its slow starter back. Run the
  sweep, not `e2e core`.
- **Don't convert checks into migrations.** It is the obvious consolidation and it is a phase
  error — see "Messages, not migrations" above. The rationale is written into
  `checks/README.md` and `results.sh` as well; if you find yourself proposing it, all three
  already say no.
- **Don't collapse two env flags because they look redundant.** `DECREE_SIDECAR` and
  `DECREE_DAEMON` read as duplicates; they were never set on the same container, and merging them
  silently turned `probe_caddy` into a no-op inside `decree` — which is where triage runs every
  service's test. Grep for what actually *sets* a variable before deciding two of them are one.
- **The value is in running the quests, not in the harness.** Every real bug this effort found —
  ollama installed with no models, hermes crying wolf on a GPU-less host, the disabled Caddy probe
  — came from bringing a quest up and looking, not from adding test infrastructure. When e2e work
  starts growing faster than the findings it produces, stop and go run something.

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
  `run-all.sh` fails+names a failing suite, `container-health.sh` (driven by a fake `docker`)
  trips on a bad container, and e2e's `collect_results` (sourced from `src/test/e2e/results.sh`)
  grades a failed, dead-lettered, or entirely absent check as a failure and copies its evidence
  out. New e2e grading logic ⇒ add a case here.
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

Go services carry their own `go test` suite (e.g. `services/automation/webhook/main_test.go`). Adhoc
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
