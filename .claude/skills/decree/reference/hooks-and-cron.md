# Hooks and Cron Reference

## Lifecycle Hooks

Configured in `config.yml`:

```yaml
hooks:
  beforeAll: ""      # Once before all processing
  afterAll: ""       # Once after all processing
  beforeEach: ""     # Before every message attempt
  afterEach: ""      # After every message attempt (success or failure)
  onDeadLetter: ""   # When a message is dead-lettered
```

### Firing Semantics

- `beforeAll` / `afterAll` — fire once per `decree process` run
- `beforeEach` / `afterEach` — fire before and after **every** message attempt (including failures)
- `onDeadLetter` — fires exactly once when a message moves to `inbox/dead/` after exhausting all retries; does not fire on `beforeEach` failures

### Hook Environment Variables

All hooks receive the standard variables plus:

| Variable                    | Description                                                  |
|-----------------------------|--------------------------------------------------------------|
| `DECREE_HOOK`               | Hook type name                                               |
| `DECREE_ATTEMPT`            | Current attempt number (`beforeEach`/`afterEach`)            |
| `DECREE_MAX_RETRIES`        | Configured max retries (`beforeEach`/`afterEach`)            |
| `DECREE_ROUTINE_EXIT_CODE`  | Routine exit code (`afterEach` only)                         |
| `DECREE_FINAL_ATTEMPT`      | `"true"` on the last attempt (`afterEach` only)              |
| `DECREE_TRIGGER`            | How the run was initiated (`inbox`, `cron:<stem>`, `chain`)  |

`onDeadLetter` also receives `DECREE_ATTEMPT` (= `max_retries`), `DECREE_MAX_RETRIES`,
`DECREE_ROUTINE_EXIT_CODE`, and `DECREE_TRIGGER`.

### What This Repo Wires

Both daemons point at the same three scripts in `automation/lib/hooks/` — there are no
per-daemon or per-routine hooks, and a new routine inherits all of this for free:

| Hook           | Script              | Does |
|----------------|---------------------|------|
| `beforeEach`   | `config-watch.sh`   | Restarts the container when `config.yml` changed under it |
| `afterEach`    | `afterEach.sh`      | Pushes metrics to Pushgateway + a summary line to Loki; clears the alert marker on success |
| `onDeadLetter` | `onDeadLetter.sh`   | Queues an ntfy alert (via the `notify` routine) when a routine exhausts its retries |

`onDeadLetter.sh` is the only alerting path for "a routine gave up", and two things about it are
load-bearing:

- **It writes to `outbox/`, like everything else the daemon produces — never `inbox/`.** The
  relay is what gives the alert a real chain and seq, keeps it inside the depth accounting, and
  leaves it chainable by a later routine. The trade-off is latency: the outbox is relayed as
  part of a *later* run, so an alert waits for the next routine to fire on that daemon (~10
  minutes on the backup daemon, whose busiest cron is `workspace-sync` at `*/10`). Tighten a
  cron if that is too slow.
- **It exits early when the dead-lettered routine is `notify` itself.** Otherwise an unreachable
  ntfy would have every failed alert queue another alert.

Repeat failures are rate-limited to one alert per routine per `DECREE_ALERT_COOLDOWN_MIN`
(default 360). The marker lives at `runs/.alert-state/<routine>` and `afterEach.sh` deletes it on
any success, so a routine that recovers and breaks again alerts immediately. Recovery itself is
not announced.

Because `notify` does the delivery, both daemons need `NTFY_*` (and the optional `TELEGRAM_*`
fallback) in their environment — see the two `environment:` blocks in
`services/automation/docker-compose.exist.yml`.

## Cron Scheduling

Every daemon has a templates-directory + active-directory pair, though the two live in
different places depending on the daemon:

- **`automation` (main daemon)** — templates in the top-level `automation-examples/cron/`
  (tracked), active triggers in the top-level `automation/cron/` (gitignored; part of the
  wholesale mount into the container, not a separate read-only overlay)
- **`automation-backup`** — both stay in its own project dir:
  `services/automation/backup/cron.example/` (tracked) and
  `services/automation/backup/cron/` (gitignored, read-only mount)

Cron files are `.md` files with a `cron` frontmatter field. Extra keys are passed
as environment variables to the routine:

```markdown
---
cron: "0 2 * * *"
routine: volume-backup
VOLUMES: "my_volume_name"
TARGETS: "seaweedfs:8333"
---
```

To activate: copy from `cron.example/` → `cron/`, then restart the decree container.
Never edit `cron.example/` files directly — they are templates for users to copy and
customise. The `.example_` suffix prevents `existential.sh` from auto-rendering them.

### Common Expressions

| Expression      | Meaning              |
|-----------------|----------------------|
| `* * * * *`     | Every minute         |
| `0 * * * *`     | Every hour           |
| `0 2 * * *`     | Daily at 2:00 AM     |
| `0 2 * * 0`     | Weekly on Sunday     |
| `0 2 1 * *`     | Monthly on the 1st   |
| `*/15 * * * *`  | Every 15 minutes     |

`decree daemon` monitors `cron/` and `inbox/` continuously.
`decree cron list` shows live schedule status (last run, next fire time).
