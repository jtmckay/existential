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

## Cron Scheduling

Cron-triggered messages are `.md` files in `.decree/cron/` with a `cron` frontmatter field:

```markdown
---
cron: "0 9 * * 1-5"
routine: develop
---
Run the weekday morning task.
```

### Common Expressions

| Expression      | Meaning              |
|-----------------|----------------------|
| `* * * * *`     | Every minute         |
| `0 * * * *`     | Every hour           |
| `0 9 * * *`     | Daily at 9:00 AM     |
| `0 9 * * 1-5`   | Weekdays at 9:00 AM  |
| `0 0 * * 0`     | Weekly on Sunday     |
| `0 0 1 * *`     | Monthly on the 1st   |
| `*/15 * * * *`  | Every 15 minutes     |

`decree daemon` monitors `.decree/cron/` and `.decree/inbox/` continuously.
`decree cron list` shows live schedule status (last run, next fire time).
