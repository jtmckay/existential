# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.
**Keep it current.** Whenever you add or remove a service, script, or change the repo
structure in a way described here, update the relevant section before finishing the task.

---

## Project Overview

Existential is a curated homelab stack: AI tools, workflow automation, note-taking, file
management, and productivity applications. All services are Docker containers on a bridge
network named `exist`.

---

## Directory Structure

```
ai/           AI tools
services/     Core applications
nas/          Storage layer
hosting/      Infrastructure
automations/  Decree automation engine (working directory)
src/          Setup and utility scripts
decree/       Decree source code (cloned, read-only reference)
site/         Docusaurus documentation
graveyard/    Archived/deprecated solutions
```

### ai/
`chatterbox` `libreChat` `ollama` `vllm` `whisper`

### services/
`actualBudget` `appsmith` `dashy` `decree` `ghost` `immich` `itTools` `logseq`
`lowcoder` `mealie` `nocoDB` `ntfy` `rabbitMQ` `vikunja` `windmill`

### nas/
`collabora` `minIO` `nextcloud` `redis` *(trueNAS is external — config note only)*

### hosting/
`caddy` `cloudflare` `portainer` `uptimeKuma`

### automations/ (Decree working directory)
Mounted into the decree container at `/work/.decree`.

```
automations/
├── config.yml          Routine registry, hooks, AI tool config
├── router.md           Prompt template for automatic routine selection
├── processed.md        Tracks completed migrations
├── routines/           Routine shell scripts
├── hooks/              Lifecycle hook scripts (beforeAll/afterAll/etc.)
├── lib/                Shared shell helpers (precheck.sh, etc.)
├── cron/               Scheduled trigger files
├── inbox/              Message queue (dead/ subdir for failed messages)
├── emails/             Archived email messages (written by gmail routine)
└── runs/               Execution logs — one dir per message (audit trail)
```

### src/
```
src/
├── generate-compose.py         Merges enabled services → docker-compose.yml
├── interactive_cli_replacer.sh Replaces EXIST_CLI placeholders interactively
├── generate_hex_key.sh         Hex key generator utility
├── generate_password.sh        Password generator utility
├── run_initial_setup.sh        Post-startup service initialization
├── create_vikunja_user.sh      Vikunja user creation
├── setup/
│   ├── actual-budget.sh        Actual Budget credentials setup (saves accounts.json)
│   ├── gmail-chase-cron.sh     Interactive Gmail→Chase→Actual Budget cron file generator
│   ├── gmail-sync.sh           Gmail OAuth setup (calls gmail-labels.sh at end)
│   ├── gmail-labels.sh         Sync Gmail label name→ID cache to secrets/gmail/labels.json
│   ├── ntfy.sh                 ntfy integration setup
│   └── rclone.sh               rclone remote configuration
└── test/
    ├── run-all.sh              Test suite orchestrator
    ├── test-syntax.sh          Syntax check all src/ scripts
    ├── test-gmail.sh           Validate Gmail credentials
    ├── test-ntfy.sh            Validate ntfy connectivity
    └── test-rclone.sh          Test rclone remote connectivity
```

---

## Setup

### Full setup (first run)
```bash
./existential.sh
```

1. Finds all `.example` files and creates counterparts (skips existing; dirs first, then files)
2. Replaces `EXIST_` placeholders interactively (`EXIST_CLI`) or automatically — reads
   `EXIST_DEFAULT_*` values from root `.env.exist`
3. Merges enabled services into a unified `docker-compose.yml` via the existential-adhoc container
4. Generates a master `.env` at the repo root by merging `.env.exist` with all enabled
   service `.env` files (auto-loaded by Docker Compose for variable substitution)

### Targeted commands
```bash
./existential.sh --force        # Regenerate existing files too
./existential.sh examples       # Only process .example files
./existential.sh compose        # Only regenerate docker-compose.yml and master .env
./existential.sh setup actual-budget    # Actual Budget credentials setup (saves accounts.json)
./existential.sh setup gmail            # Gmail OAuth setup (also runs gmail-labels)
./existential.sh setup gmail-chase-cron # Gmail→Chase→Actual Budget cron file generator
./existential.sh setup gmail-labels     # Sync Gmail label name→ID cache (re-run after adding labels)
./existential.sh setup rclone           # Configure remote file storage
./existential.sh setup ntfy             # ntfy integration setup
./existential.sh test           # Run test suite
```

### Manual service setup
```bash
cp services/foo/.env.example services/foo/.env
# edit .env, then:
docker compose up -d
```

---

## Placeholder System

| Placeholder | Behavior |
|---|---|
| `EXIST_CLI` | Prompts user for input during setup |
| `EXIST_24_CHAR_PASSWORD` | Generates a unique 24-character password |
| `EXIST_32_CHAR_HEX_KEY` | Generates a unique 32-character hex key |
| `EXIST_64_CHAR_HEX_KEY` | Generates a unique 64-character hex key |
| `EXIST_TIMESTAMP` | Current timestamp (`YYYYMMDD_HHMMSS`) |
| `EXIST_UUID` | UUID |
| `EXIST_DEFAULT_*` | Value of matching variable from root `.env.exist` |

---

## Service Enablement

Toggle services via `EXIST_ENABLE_*=true/false` in the root `.env.exist`, then:

```bash
./existential.sh compose
```

`src/generate-compose.py` runs in the `existential-adhoc` container. It reads
`EXIST_ENABLE_*`, discovers `docker-compose.yml` files at depth 2, adjusts relative
paths from the repo root, and merges services/volumes/networks. The previous
`docker-compose.yml` is archived as `docker-compose-<timestamp_ms>.yml` before writing.

---

## Architecture

- Each service has its own `docker-compose.yml` and `.env` file
- All services connect to the `exist` bridge network
- Secrets are stored in `services/<name>/secrets/` (gitignored)
- The `existential-adhoc` container (profile: `adhoc`) handles setup tasks requiring
  non-standard tools — mounts `src/` at `/src` and the repo at `/repo`
- Documentation lives in `site/` (Docusaurus)

---

## Decree (Automations)

Use the `/decree` command for all Decree-related work: creating routines, cron jobs,
webhooks, hooks, or answering questions about how the pipeline works.

**Invoke `/decree` proactively** whenever the user is:
- Adding or modifying anything in `automations/`
- Adding or modifying anything in `services/decree/`
- Asking how to automate something, schedule a task, or trigger a workflow
- Asking how decree works

Quick reference:
- Routines: `automations/routines/<name>.sh` + registered in `automations/config.yml`
- Cron jobs: `automations/cron/<name>.md`
- Webhook endpoints: `services/decree/webhook/config.yml`
- Run commands via: `docker exec decree decree <command>`

---

## Testing Services
```bash
docker ps | grep <service_name>   # Check status
docker logs <container_name>      # View logs
./existential.sh test             # Run integration test suite
```

---

## Keeping This File Current

Update CLAUDE.md in the same task whenever you:
- **Add a service** — add it to the correct category in the directory structure section
- **Remove a service** — remove it from that section
- **Add or remove a script** in `src/` — update the src/ tree
- **Add or remove a Decree routine or cron file** — no change needed here; those are
  covered by the `/decree` command which reads the live files
- **Change a setup command** (e.g. new `./existential.sh setup <name>` subcommand) —
  update the Targeted commands section
- **Add a new top-level directory** — add it to the directory structure overview

Do not let CLAUDE.md describe things that no longer exist. If you notice a stale entry
while working on an unrelated task, fix it in the same commit.
