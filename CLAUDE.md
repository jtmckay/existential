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
`chatterbox` `hermes` `librechat` `lightrag` `mcp` `ollama` `open-webui` `whisper`

### services/
`actual-budget` `appsmith` `dashy` `decree` `immich` `it-tools` `lowcoder`
`mealie` `nocodb` `ntfy` `vikunja`

### nas/
`collabora` `minio` `nextcloud` `redis` *(trueNAS is external — config note only)*

### hosting/
`caddy` `cloudflare` `grafana` `loki` `pihole` `portainer` `prometheus` `uptime-kuma`

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
├── outbox/             Follow-up messages written by routines; decree relays to inbox
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
│   ├── gmail-transactions-cron.sh  Interactive Bank Alert→Gmail→Actual Budget cron file generator
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
./existential.sh setup gmail-transactions-cron # Bank Alert→Gmail→Actual Budget cron file generator
./existential.sh setup gmail-labels     # Sync Gmail label name→ID cache (re-run after adding labels)
./existential.sh setup rclone           # Configure remote file storage
./existential.sh setup ntfy             # ntfy integration setup
./existential.sh test           # Run test suite
./existential.sh validate       # On-demand: convention + drift checks
./existential.sh validate conventions  # Slugs synced across compose/piHole/Caddy/dashy
./existential.sh validate drift        # What re-rendering would change in your .env / compose files
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

An `EXIST_CLI` prompt can opt into a fallback by adding a comment immediately
above the line: `# DEFAULT_FROM: EXIST_DEFAULT_FOO`. If the user enters blank,
the value of `EXIST_DEFAULT_FOO` (already written earlier in the same file) is
used. Used today for `EXIST_DEFAULT_PEER_HOST_IP` defaulting to `LOCAL_HOST_IP`.

---

## Container naming convention

Every container in a service's compose file must be prefixed with the
service's slug (the folder name). For a service in `hosting/loki/`:

- `loki` (the primary container — slug-only is fine)
- `loki-promtail` ✓
- `promtail` ✗ — opaque, doesn't say which service it belongs to

Reason: reading `docker ps` should make it immediately clear which service
each container belongs to. No having to look up what "pushgateway" or
"promtail" is.

The same rule applies to support filenames where the container's identity
is part of the name (e.g., `loki-promtail-config.yaml`, not
`promtail-config.yaml`). Files specific to the primary service can use the
slug alone (e.g., `loki-config.yaml`).

The validation script (`./existential.sh validate conventions`) catches
container names that don't start with their folder's slug.

---

## Networking convention

Two layers — pick the right one for the call site.

**Browser / cross-machine traffic → `https://<slug>.internal`** (the slug matches
the service's `container_name`, lowercase-hyphenated):

- **piHole** (`hosting/pihole/docker-compose.yml`) holds a record per slug,
  active line pointing at `EXIST_DEFAULT_LOCAL_HOST_IP` and a commented PEER
  alternative. Flip the comment to migrate a service between machines.
- **Caddy** (`hosting/caddy/Caddyfile`) fronts every slug with `tls internal`
  and reverse-proxies to `<container>:<port>`. Browsers see a cert from
  Caddy's internal CA — install the root once per device for green locks.
- **Dashy** (`services/dashy/dashy-conf.yml`) links every navigable slug.
- **`.env.exist`** holds `EXIST_DEFAULT_LOCAL_HOST_IP` (this machine) and
  `EXIST_DEFAULT_PEER_HOST_IP` (the other machine; defaults to LOCAL).

**Container-to-container traffic → `http://<container>:<port>`** (Docker's
built-in service DNS on the `exist` network):

- Service env vars in `*/docker-compose.yml.example` and `.env.example` use
  this form (e.g., `OLLAMA_BASE_URL=http://ollama:11434`).
- Automation routines (`automations/routines/*.sh`) and shared libs use this
  form for their default `${X_URL:-http://service:port}` fallbacks.
- Faster (no Caddy hop), simpler (no TLS), and doesn't need Caddy CA trust
  inside the calling container — which would otherwise require per-image
  surgery for each base distro / runtime.

When adding a service, the slug appears in three convention files (piHole,
Caddy, Dashy if navigable). Cross-service references inside service env vars
stay on Docker DNS. Run `./existential.sh validate conventions` to verify
the three are in sync.

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
