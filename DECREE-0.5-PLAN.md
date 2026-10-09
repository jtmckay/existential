# Plan: move automation to decree 0.5, and delete what 0.5 makes unnecessary

**Goal.** `automation` and `automation-backup` run decree **0.5** (pin `v0.5.0-beta.4` or later until 0.5.0 ships), and the
webhook becomes **decree-go-rest**. Net result: roughly **3,000 lines deleted** and no new code beyond
small machine files. Routine *logic* is not rewritten; it is moved, and its 0.4 plumbing is cut.

Read first: decree 0.5's skill (`decree init` writes it to `.claude/skills/decree/`) and its rule
**"start with the simplest machine"**. Almost every routine becomes a one-state machine.

## What 0.5 replaces

| 0.4 here | 0.5 | Delete |
| --- | --- | --- |
| `routine:` + every frontmatter key as an env var | `machine:` + `params:`; the machine declares typed `data` with defaults; scripts read `DECREE_DATA_<NAME>` | the `${x:-default}` lines at the top of each routine (defaults move to `data`) |
| `shared_routines/<name>.sh` | `machines/<name>.yml` (one state) + `scripts/<name>.sh` (the same script) | — |
| `config.exist.yml` (`shared_routines: enabled`, `max_attempts`, `commands`, hooks, `default_routine`) | Nothing. A machine that nothing triggers costs nothing; "enabled" = a cron file or endpoint points at it. Retries are `attempts:` on the one state that needs them. | `decree/config.exist.yml` (132) |
| `DECREE_PRE_CHECK` blocks + `lib/precheck.sh` | A missing tool fails the run, and the log says `command not found`. Add a `precheck` state only to a routine where that is not clear enough. | 311 lines of blocks + 28 |
| `message_file`, `message_dir`, `message_id`, `chain`, `seq` | `DECREE_MESSAGE`, `DECREE_RUN_DIR`, `DECREE_MESSAGE_ID`; `chain`/`correlation_id` → W3C `TRACEPARENT`, which `decree emit` carries across hops | the `correlation_id` plumbing |
| Writing `.decree/outbox/*.md` to chain | `decree emit --machine X --param k=v`; the state lists `emits: [X]` so `decree check` and `decree graph` see the chain | outbox dir handling in each chaining routine |
| `default_routine: route-failed` | A message with an unknown or missing machine becomes a `failed` run with `invalid_message` and the reason, visible in `decree status` | `route-failed.sh` (65) |
| `onDeadLetter` hook → ntfy | A Grafana alert on `increase(decree_runs_total{state="failed"}[10m]) > 0` (the metric from step 7) with an ntfy webhook contact point. Nothing routes Prometheus alerts to ntfy today, so this is the one new piece of config. | `hooks/onDeadLetter.sh` (104) |
| `afterEach` hook → Pushgateway + Loki | Alloy ships `runs/**/events.jsonl` and `runs/**/*.log` to Loki, and its `stage.metrics` turns each `run_finished` line into Prometheus metrics on Alloy's own `/metrics` (step 7). decree 0.5 has no exporter on purpose: the event log is the telemetry. | `hooks/afterEach.sh` (107), `hooks/config-watch.sh` (25) |
| `clean-runs` (keep 10 per group) | `decree prune --older-than 7d` from a one-line cron'd script (Loki keeps the history) | `clean-runs.sh` (92 → ~5) |
| `check-disabled-runs` | Nothing is "disabled" any more; invalid messages are failed runs, alerted above | `check-disabled-runs.sh` (44) |
| `routines-snapshot` (`decree routine` listing for hermes) | `decree graph`'s `.decree/graph/system.md` lists every machine with its description and chains; the params are each machine's `data`. Copy `system.md` and `machines/*.yml` to `workspace/ai/decree/` | `routines-snapshot.sh` (68 → ~5) |
| Migration gate (entrypoint waits on `exist.test.sh`, then `decree process`) | Each migration's machine starts with a `wait_for_<service>` state: `script: { name: wait_for_ollama, timeout: 10m }`. The entrypoint just `exec decree daemon` (it runs migrations itself). | `migration-gate.sh` (102), ~50 lines of `entrypoint.sh`, the `DECREE_CONTAINER` checks |
| Go webhook (`main.go`, tests, README) | `decree-go-rest` image with `daemon: { enabled: false }`, sharing `.decree/` with `automation` | ~1,850 lines; keep only `config.yml` |
| `decree-ui.ts` (Lowcoder app generated from the webhook config) | `DECREE_GO_REST_OPENAPI=true` serves `/openapi.json`; add it in Lowcoder as an OpenAPI data source | `decree-ui.ts` (232), `exist.decree-ui.sh` (16) |
| `router.md`, `commands.ai_router` | `model` decisions with a router machine, only where a routine routes between other machines | `router.md` (14) |
| Ad-hoc state directories (`STATE_DIR`, per-routine seen-files) | `.decree/store/<machine>/` as `$DECREE_STORE`, each file declared under the machine's `store:`; `decree check` warns about undeclared ones | the per-routine path plumbing |
| `.claude/skills/decree/` (554, for 0.4) | the 0.5 skill from `decree init`, plus a 10-line existential note (lib/, env, hermes) | ~540 |

## Steps (each one leaves the stack working)

1. **Image.** `services/automation/decree/Dockerfile`: `cargo install --locked --git https://github.com/jtmckay/decree --tag v0.5.0-beta.4`. Entrypoint: create the passwd entry, then `exec decree daemon --interval 2s`. Nothing else.
2. **Two projects, not one shared `runs/`.** `automation` and `automation-backup` each get their own `.decree/` (own `machines/`, `cron/`, `runs/`). This removes the "two daemons share runs/" cases that `clean-runs` documents.
3. **Layout.** In `automation/`: `machines/`, `scripts/` (was `shared_routines/`), `lib/` (unchanged, now `$DECREE_LIB`), `cron/`, `migrations/`, and `.decree/env` for non-secret config (`NTFY_URL`, `EXIST_OLLAMA_URL` defaults). Secrets stay in compose `environment:`, which wins over `.decree/env`.
4. **Convert routines** (one commit per handful, `decree check` after each). Recipe, for `notify`:
   ```yaml
   # machines/notify.yml
   name: notify
   description: Send the message body to ntfy (and Telegram if configured).
   data:
     ntfy_topic:    { type: string, default: decree }
     ntfy_title:    { type: string, default: "" }
     ntfy_priority: { type: string, enum: ["", min, low, default, high, urgent], default: "" }
     ntfy_tags:     { type: string, default: "" }
   initial: send
   states:
     send:
       invoke: notify
       transitions: { done: done }
     done:   { final: true }
     failed: { final: true }
   ```
   Script: delete the pre-check block, replace `ntfy_title="${ntfy_title:-}"` with `ntfy_title="$DECREE_DATA_NTFY_TITLE"`, body from `$DECREE_MESSAGE`. **0.5 rejects params a machine does not declare**, so every producer (webhook config, gmail, telegram, cron files) must send declared names only: grep each routine's frontmatter keys into its `data`.
   Chaining routines (`file-router`, `hermes-router`, `idea-workup`, `note-triage`, `gmail-sync`, `rss-poll`, …): outbox writes become `decree emit`, plus `emits:` on the state.
5. **Cron and migrations.** `routine: x` → `machine: x`, extra keys under `params:`. `processed.md` keeps its lines. Give migrations 23–27 their `wait_for_*` state (step 6 of the table) and delete the gate.
6. **Webhook → decree-go-rest.** Build its image (repo `jtmckay/decree-go-rest`, `Dockerfile`), mount the shared `automation/` project at `/project`, `daemon: { enabled: false }`. Config: `frontmatter: { routine: x, k: v }` → `message: { machine: x, params: { k: v } }`; `/files`' own `secret:` → `secret_env:`; set `DECREE_GO_REST_OPENAPI=true` for Lowcoder.
7. **Observability.** In `hosting/loki/loki-alloy-config.alloy`, replace the `routine.log`/`message.md` targets with `runs/**/events.jsonl` (`stage.json`; labels `machine`, `type`) and `runs/**/[0-9]*.log`. For Prometheus, add a `stage.metrics` block that matches `type="run_finished"` lines as decree's docs describe (`docs/reference/observability.md`, Metrics):
   - `decree_runs_total{machine, state}`, a counter (success is `state="done"`);
   - `decree_run_duration_milliseconds{machine, state}`, a histogram from `duration_ms`.

   decree's `examples/observability/config.alloy` has this block, tested; copy it.

   Set `max_idle_duration` to a few days so a daily backup's series do not expire between runs, and have Prometheus scrape Alloy's `/metrics`. Then:
   - `BackupNotRun` becomes `increase(decree_runs_total{machine=~"db-backup|volume-backup|sqlite-backup", state="done"}[48h]) == 0`;
   - `decree-overview.json` swaps `instance` for `machine`;
   - `decree-run-detail.json` reads `events.jsonl` in Loki.

   Pushgateway stays for triage's own `exist_service_healthy`.
8. **Hermes.** Replace `outbox-relay` with a decree-go-rest endpoint hermes POSTs to (its own `secret_env`), so hermes still never mounts `automation/`. If hermes cannot POST, keep `outbox-relay` but make it `decree emit`.
9. **Delete** everything in the table's last column, the 0.4 `runs/` (already in Loki), and the 0.4 skill. Update `site/docs/decree/*` and `writing-a-routine.md` ("routine" → machine + script).

## Decide before starting

- **`hermes-router`'s departments** are discovered from `ai/hermes/profiles/*`, but a `model` decision's options are fixed in the machine. Simplest: keep it a script that runs `decree emit --machine hermes-dept --param profile=<picked>`; a department is still "add a directory".
- **Pre-release pin.** 0.5 is a beta; pin the tag in both Dockerfiles and bump deliberately.

## Done when

- `decree check` passes in both projects; `decree graph` shows every chain (`emits`).
- Every enabled cron fires, a webhook POST runs its machine, migrations 23–27 are in `processed.md`.
- A forced failure produces an ntfy alert from Grafana, not from a hook.
- `rg -n 'routine:|DECREE_PRE_CHECK|message_file|outbox' automation services/automation` finds nothing but docs history.

## After the move: a personal newsletter (replaces `rss-poll`)

decree's `examples/newsletter/` is the basic version, and existential's follows its machine exactly. It has three states in a straight line, run weekly by cron: `gather → write → deliver`. Differences for the stack:

- **`gather`** is TypeScript through `tsx`, reusing `lib/rss.ts` (no Python here). Feeds are in `lib/newsletter/feeds.txt`. Links already sent are in `$DECREE_STORE/seen.tsv`, declared under the machine's `store:` (decree 0.5.0-beta.3), not in the run folder.
- **`write`** asks `EXIST_MODEL_CHAT` at `EXIST_OLLAMA_URL_CHAT` (falling back to `EXIST_OLLAMA_URL`), with taste in `lib/newsletter/taste.md`, plain prose the user edits.
- **`deliver`** writes `workspace/newsletter/<date>.md`. Nextcloud shows it, and since decree writes it straight to disk it fires no file event. The ping is optional: `decree emit --machine notify` with the issue's top lines, and `emits: [notify]` on the state. No second ntfy client.
- **Delete `rss-poll`:** `shared_routines/rss-poll.sh` (131), `automation-examples/cron/rss-poll.md` and `src/quests/rss-poll.md`. It was a reference example of per-item alerts, and nothing enabled uses it. If an instant alert for one pattern is ever wanted again, it's a second cron file on the same machine with a `filter` param, added only then.
- **Grow it** only as decree's example README lists, when a real issue shows the need: `nothing_new`, `attempts: [local, claude]`, per-item scoring, editions, ratings through a decree-go-rest endpoint.
