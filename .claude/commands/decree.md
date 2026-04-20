# Decree Skill

Use this skill when the user asks about Decree — how it works, how to create a routine,
cron job, webhook, hook, or anything related to the automation pipeline in this repo.
Also use proactively when the user is editing files in `automations/` or
`services/decree/`.

---

## Your Role When Invoked

1. Read the user's request. If it's not obvious what they want (create routine / cron /
   webhook / hook / question), ask one clarifying question before proceeding.
2. Read any relevant existing files before writing (e.g. `automations/config.yml` before
   adding a routine, `services/decree/webhook/config.yml` before adding an endpoint).
3. Create or edit the files as described below.
4. After writing, summarize exactly what was created and — for routines — remind the user
   to verify the pre-check: `docker exec decree decree routine <name>`.

---

## Project Layout

All Decree state lives in `automations/`. The container mounts it at `/work/.decree`.

| Repo path | Container path | Purpose |
|---|---|---|
| `automations/routines/` | `/work/.decree/routines/` | Routine shell scripts |
| `automations/config.yml` | `/work/.decree/config.yml` | Registry, hooks, AI config |
| `automations/cron/` | `/work/.decree/cron/` | Cron trigger files |
| `automations/inbox/` | `/inbox` (webhook) | Message queue |
| `automations/hooks/` | `/work/.decree/hooks/` | Lifecycle hook scripts |
| `automations/lib/` | `/work/.decree/lib/` | Shared shell helpers |
| `automations/runs/` | `/work/.decree/runs/` | Execution logs (audit trail) |
| `automations/inbox/dead/` | — | Dead-lettered messages |
| `services/decree/webhook/config.yml` | `/app/config.yml` (webhook container) | Webhook endpoints |

Run Decree commands via: `docker exec decree decree <command>`

---

## Creating a Routine

### Step 1 — Write `automations/routines/<name>.sh`

Use this exact template. Never deviate from the structure — Decree parses it.

```bash
#!/usr/bin/env bash
# <Title>
#
# <Short description — appears in `decree routine` list>
# <Optional additional description lines>
#
# Example cron trigger (automations/cron/<name>.md):
#
#   ---
#   cron: "*/15 * * * *"
#   routine: <name>
#   my_param: value        # becomes env var $my_param
#   ---
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "<name>" "curl not found"
    precheck_pass "<name>"
    exit 0
fi

# Custom params — Decree discovers these automatically.
# Pattern MUST be: varname="${varname:-default}" (exact self-referential form).
# All custom params must be grouped here; Decree stops scanning at the first
# non-matching line. Values come from message/cron frontmatter as env vars.
my_param="${my_param:-default_value}"

# Implementation
```

**Critical rules for custom param discovery:**
- Pattern must be `name="${name:-default}"` — the variable name must appear on both sides
- Group all custom params together after the precheck block; Decree stops at the first non-matching line
- Standard params are excluded automatically: `message_file`, `message_id`, `message_dir`, `chain`, `seq`, `spec_file`
- Empty default (`${var:-}`) means the param is optional with no default

**Precheck helpers** (from `automations/lib/precheck.sh`):
- `precheck_pass "<name>"` — logs OK and exits 0
- `precheck_fail "<name>" "<reason>"` — logs FAIL, prints to stderr, exits 1

**This project uses `opencode` as the AI tool** (`DECREE_AI=opencode` in the container).
For routines that invoke AI: `opencode run "Read ${message_file} and ..."`.
For non-AI routines (data pipelines, sync tasks, notifications): call tools directly.

**Routine chaining:** routines must ONLY write new messages to `automations/outbox/`
(`/work/.decree/outbox/` in the container) — never directly to `inbox/`. Writing to the
outbox lets Decree tag the message with the current recursion depth and process it
depth-first. Writing directly to the inbox bypasses that tracking and will cause
incorrect depth counts. The inbox is for external entry points only (cron daemon,
webhooks).

### Step 1b — Companion scripts (optional)

If the routine needs logic beyond what bash handles cleanly (e.g. a Node.js API client),
put those files in `automations/lib/<domain>/` as TypeScript (`.ts`). One subdirectory
per service or domain:

```
automations/lib/
├── precheck.sh                  ← shared bash helper (top-level, not domain-specific)
├── package.json                 ← deps for all lib TS files (tsx, @types/node, etc.)
├── tsconfig.json                ← shared TS config
├── actual-budget/
│   ├── setup.ts
│   └── post-transaction.ts
└── notes/
    └── compile-notes.sh
```

**Runtime:** `tsx` (no compile step). It is listed in `automations/lib/package.json` and
installed at `automations/lib/node_modules/`. The decree container mounts `automations/`
at `/work/.decree/`, so invoke it as:

```bash
/work/.decree/lib/node_modules/.bin/tsx /work/.decree/lib/<domain>/<file>.ts
```

**Dependencies:** add runtime deps to `automations/lib/package.json`. Always pin to an
exact version number — never use `"latest"`. Check the currently installed version with
`docker exec decree cat /work/.decree/lib/node_modules/<pkg>/package.json | grep version`
and use that value. The setup script runs `npm install` on first use; a single
`node_modules` is shared across all lib scripts.

**Local IDE support:** after adding deps to `package.json`, run
`docker exec decree sh -c "cd /work/.decree/lib && npm install"` to populate
`automations/lib/node_modules/` on the host (npm is not installed on the host directly).

Never inline companion logic as a heredoc inside a shell script.

### Step 2 — Register in `automations/config.yml` AND `automations/config.yml.example`

Add the routine to the `routines:` section **in both files** (alphabetical by convention).
In `config.yml`, set `enabled: true` (it's a live environment). In `config.yml.example`,
set `enabled: false` (it ships disabled; a setup script or the user enables it):

```yaml
# automations/config.yml  ← enabled: true (live)
routines:
  <name>:
    enabled: true

# automations/config.yml.example  ← enabled: false (template default)
routines:
  <name>:
    enabled: false
```

A routine that exists on disk but is NOT in this registry will not be discoverable
or executable. After editing, the daemon picks up changes automatically via the
`config-watch.sh` hook (beforeAll/afterAll).

Alternatively: `docker exec decree decree routine-sync` auto-discovers all scripts.

### Setup scripts must enable the routine

If the routine has a companion setup script in `src/setup/`, the script must enable the
routine in `automations/config.yml` after a successful run. Add this block at the end of
the setup script (before the final success message), adjusting the routine name:

```bash
CONFIG="${SCRIPT_DIR}/../../automations/config.yml"
if [ -f "$CONFIG" ]; then
    awk '
        /^  <name>:$/ { found=1 }
        found && /enabled:/ { sub(/enabled: .*/, "enabled: true"); found=0 }
        { print }
    ' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    echo "  Routine '<name>' enabled in automations/config.yml."
fi
```

This mirrors the pattern in `src/setup/ntfy.sh` and `src/setup/actual-budget.sh`.

### Verify

```bash
docker exec decree decree routine <name>   # shows detail + runs pre-check
docker exec decree decree verify           # runs all pre-checks
```

---

## Creating a Cron Job

Create `automations/cron/<name>.md`:

```markdown
---
cron: "*/15 * * * *"
routine: <routine-name>
MY_ENV_VAR: value
---

Optional description body (becomes $message_file body when the cron fires).
```

**How cron fields work (from Decree source):**
- `cron`: standard 5-field expression — Decree prepends `0` for seconds internally
- `routine`: which routine to run (must be registered and enabled in config.yml)
- Every other field becomes an env var injected into the routine — this is how you
  parameterize a routine per-cron without writing separate scripts
- `cron` and `routine` are stripped; everything else passes through as custom fields

**Common schedules:**
```
* * * * *        Every minute
*/15 * * * *     Every 15 minutes
0 * * * *        Every hour
0 9 * * *        Daily at 9:00 AM UTC
0 9 * * 1-5      Weekdays at 9:00 AM UTC
0 4 * * *        Daily at 4:00 AM UTC
0 0 * * 0        Weekly on Sunday
```

**Example — two cron files targeting different Gmail labels:**
```
automations/cron/gmail-sync.md          GMAIL_LABEL_FILTER: INBOX
automations/cron/gmail-sync-work.md     GMAIL_LABEL_FILTER: Work
```

The daemon fires every minute, checks each cron file's schedule against the current
time, and enqueues an inbox message when due. A per-minute dedup guard prevents
double-firing within the same minute.

---

## Creating a Webhook Endpoint

Edit `services/decree/webhook/config.yml`:

```yaml
# Global Bearer token secret (min 16 chars). Per-endpoint secret: overrides this.
secret: <32-char-hex-key-from-env>

endpoints:
  # Static path
  - path: /my-endpoint
    frontmatter:
      routine: <routine-name>
      my_param: value

  # Dynamic path with a URL param
  - path: /my-endpoint/{id}
    # Optional: stricter per-param regex (anchored automatically, applied after default check)
    params:
      id: '[0-9a-f]{8,16}'
    frontmatter:
      routine: <routine-name>
      record_id: '{{id}}'       # {{param}} substitutes the URL param value

  # Per-endpoint secret
  - path: /external
    secret: <different-secret>
    frontmatter:
      routine: notify
```

**How webhooks work:**
- POST to the path with `Authorization: Bearer <secret>` header
- Request body (plain text/markdown) becomes the inbox message body
- Frontmatter from config is injected as YAML frontmatter at the top
- `{{param}}` in frontmatter values is substituted with the URL param
- Filename: `<timestamp_ms>-<random_hex>.md` (atomic write, no overwrites)
- The webhook container reads `automations/inbox/` via `/inbox` volume mount
- Config reload: the webhook server restarts automatically when the file changes
- Rate limit defaults: 60 req/min total, 10 failed req/min

**URL param validation (default):** `[A-Za-z0-9_\-!]+` — use `params:` for stricter patterns.

**Calling the webhook:**
```bash
curl -X POST https://<host>/my-endpoint \
  -H "Authorization: Bearer <secret>" \
  -H "Content-Type: text/plain" \
  -d "Message body here"
```

Returns `201 {"file": "<filename>", "path": "/my-endpoint"}` on success.

**Port:** `DECREE_WEBHOOK_PORT=48880` (from `services/decree/.env`).
Exposed on the host and routed via Caddy.

---

## Creating / Modifying a Hook

Hooks are routines, but they bypass the registry — they only need the script on disk.
Configure them in `automations/config.yml`:

```yaml
hooks:
  beforeAll: /work/.decree/hooks/config-watch.sh   # full container path
  afterAll: /work/.decree/hooks/config-watch.sh
  beforeEach: ''
  afterEach: ''
```

**Two ways to reference a hook:**
- **Full container path** (existing convention): scripts in `automations/hooks/` are
  referenced as `/work/.decree/hooks/<name>.sh` in config.yml
- **Relative name** (resolves through routines dir): scripts in `automations/routines/hooks/`
  are referenced as `hooks/<name>` — Decree looks for `<routines_dir>/hooks/<name>.sh`

The existing project uses full paths for everything in `automations/hooks/`.

Hook scripts live in `automations/hooks/` (or `automations/routines/hooks/`).
They receive all standard env vars plus:

| Var | When | Value |
|---|---|---|
| `DECREE_HOOK` | always | `beforeAll`, `afterAll`, `beforeEach`, `afterEach` |
| `DECREE_ATTEMPT` | beforeEach/afterEach | current attempt, 1-indexed |
| `DECREE_MAX_RETRIES` | beforeEach/afterEach | configured max retries |
| `DECREE_ROUTINE_EXIT_CODE` | afterEach only | exit code of the routine that just ran |

A single script can serve multiple hook roles — check `$DECREE_HOOK` to branch.
See `automations/hooks/config-watch.sh` for the pattern.

---

## Reference: How Decree Works

### Message lifecycle

```
migrations/01-spec.md
    ↓ decree process
inbox/D0001-1432-01-spec-0.md   ← normalized: chain/seq/id/routine filled
    ↓ beforeEach hook
    ↓ routine executes (all frontmatter fields as env vars)
    ↓ success → afterEach hook → message deleted (run dir is the record)
    ↓ failure → retry up to max_retries (default: 3), then → inbox/dead/
```

Cron fires the same way — it creates an inbox message then that message flows
through the same pipeline.

### Message ID format

`D<NNNN>-HHmm-<name>-<seq>`

- `D<NNNN>`: day counter (resets on clock wrap at midnight)
- `HHmm`: time when the chain was created
- `<name>`: derived from migration filename or cron stem
- `<seq>`: 0 for first message in chain, increments for follow-ups

### Run directory

Every message execution creates `automations/runs/<message-id>/`:
- `message.md` — the message as it was processed
- `routine.log` — combined stdout/stderr from the routine

Max log size: 2 MB (configurable via `max_log_size` in config.yml).

### Config.yml structure

```yaml
commands:
  ai_router: opencode run {prompt}     # used to auto-select routine
  ai_interactive: opencode             # used by `decree prompt`
max_retries: 3
max_depth: 10                          # max follow-up chain depth
max_log_size: 2097152
default_routine: develop               # fallback if router returns no match
hooks:
  beforeAll: /work/.decree/hooks/config-watch.sh
  afterAll: /work/.decree/hooks/config-watch.sh
  beforeEach: ''
  afterEach: ''
routines:
  my-routine:
    enabled: true
  old-routine:
    enabled: false
    deprecated: true                   # auto-set when script file disappears
```

### Routine auto-selection (router)

When a message has no `routine:` field, Decree uses `automations/router.md` as a
prompt template, populating `{routines}` and `{message}`, then calls the AI router
command. The router must return only the routine name. Falls back to
`default_routine` if AI returns an unrecognised name.

### Useful commands

```bash
# Check routine pre-checks
docker exec decree decree verify

# Run a specific routine's pre-check + detail
docker exec decree decree routine <name>

# View recent execution logs
docker exec decree decree log <id-prefix>

# Processing status
docker exec decree decree status

# Sync routine registry after adding scripts
docker exec decree decree routine-sync

# Manually trigger a routine (drop a message in inbox)
cat > automations/inbox/test.md << 'EOF'
---
routine: <name>
my_param: test_value
---
Test message body.
EOF
```
