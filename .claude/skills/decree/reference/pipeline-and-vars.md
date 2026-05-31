# Processing Pipeline and Variables Reference

## Processing Pipeline

Messages enter the inbox from three sources:
- **Cron** — decree fires a message on schedule from `cron/`
- **Webhook** — decree-webhook drops a file into `inbox/` when an HTTP request arrives
- **Outbox relay** — routines write follow-ups to `outbox/`; decree moves them to `inbox/`

Processing steps:
1. Messages in `inbox/` are processed in arrival order
2. Each message is normalized — missing fields filled in, routine selected
3. Lifecycle hooks run (`beforeEach`)
4. The selected routine executes with parameters as environment variables
5. On success: `afterEach` runs, message deleted from inbox, `run.json` written to `automations/runs/`
6. On failure: retry strategy applies. If the log contains "usage limit" + "reset", Decree waits until the reset time then retries from scratch
7. After all retries: message is dead-lettered
8. Follow-up messages from routines (outbox) are processed depth-first
9. The inbox is fully drained before moving on

## Standard Environment Variables

Set before every routine and hook:

| Variable       | Description                                             |
|----------------|---------------------------------------------------------|
| `message_file` | Path to `message.md` in the run directory               |
| `message_id`   | Full message ID (e.g., `D0001-1432-01-add-auth-0`)      |
| `message_dir`  | Run directory path (contains logs from prior attempts)  |
| `chain`        | Chain ID (`D<NNNN>-HHmm-<name>`)                        |
| `seq`          | Sequence number in the chain                            |

Custom frontmatter fields are also passed as environment variables.

### Retry Variables (token-exhaustion retry only)

| Variable                     | Description                                       |
|------------------------------|---------------------------------------------------|
| `DECREE_PREVIOUS_SESSION_ID` | Claude session ID from the prior attempt          |

## run.json

Written to the run directory after every completed run (success or dead-letter).
Not available during `afterEach` — it is written after the hook completes.

| Field        | Description                                                 |
|--------------|-------------------------------------------------------------|
| `message_id` | Full message ID                                             |
| `routine`    | Routine name used for processing                            |
| `trigger`    | How the run was initiated (`inbox`, `cron:<stem>`, `chain`) |
| `migration`  | Migration filename, if this was a migration run             |
| `attempts`   | Number of attempts made                                     |
| `exit_code`  | Exit code of the final attempt                              |
| `start`      | ISO-8601 timestamp when the run started                     |
| `end`        | ISO-8601 timestamp when the run ended                       |
| `duration_s` | Total elapsed seconds                                       |

Decree also writes `[decree] start <timestamp>` and `[decree] duration <N>s end <timestamp>`
to `routine.log` during execution — these are available to hooks before `run.json` exists.
