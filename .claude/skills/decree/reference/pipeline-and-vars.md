# Processing Pipeline and Variables Reference

## Processing Pipeline

1. Migration files in `.decree/migrations/` are read in alphabetical order
2. Each migration becomes an inbox message in `.decree/inbox/`
3. Messages are normalized — missing fields are filled in and the routine is selected
4. Lifecycle hooks run (`beforeEach`)
5. The selected routine executes with parameters as environment variables
6. On success: `afterEach` runs, the message is deleted from inbox, `run.json` is written
7. On failure: retry strategy applies. If the log contains "usage limit" + "reset", Decree waits until the reset time (SIGINT-aware, exits 130) then retries from scratch
8. After all retries: message is dead-lettered. If it was a migration, Decree stops immediately — subsequent migrations are not started
9. Follow-up messages from routines are processed depth-first
10. The inbox is fully drained before the next migration starts

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
