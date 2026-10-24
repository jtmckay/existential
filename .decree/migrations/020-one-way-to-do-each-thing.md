---
machine: develop
---
# One way to do each thing: no second Caddy, no hand-made network, no spare settings

## Overview

Every setting in `.env.exist.shared` is something a person may stop and wonder about, and
every alternative path is one more thing to keep working. Several existed only as a second
way to do something the stack already does, or did nothing at all. The stack runs on one
host with one Caddy, Compose creates the `exist` network, and ntfy's bot user is the one
publishing identity.

## Outcome

- **One Caddy, one host.** There is no peer or front-door mode: no `EXIST_PEER_HOST_IP`, no
  `Caddyfile.frontdoor-*.example`, and nothing in docs, quests or templates describes one.
  `run caddy public-domain` is the way to add public hostnames.
- **Compose owns the `exist` network.** The generated `docker-compose.yml` always declares it
  as Compose's own bridge, never `external`. No service template declares it, and no doc or
  quest says to `docker network create` it. `EXIST_NETWORK_EXTERNAL` and
  `EXIST_DOCKER_NETWORK_SUBNET` do not exist.
- **NAS storage is one setting.** `EXIST_NFS_HOST_MOUNT` is the only NFS key;
  `EXIST_NFS_SERVER_ADDRESS` and `EXIST_NFS_BASE_PATH` do not exist.
- **ntfy has one login.** Every publisher uses `EXIST_NTFY_USER` / `EXIST_NTFY_PASSWORD`, and
  that user may publish to every topic. `EXIST_NTFY_TOKEN`, `EXIST_NTFY_TOPICS` and
  `./existential.sh run ntfy setup` do not exist.
- **Notifications go to ntfy only.** `notify.sh` has no Telegram fallback, and
  `EXIST_TELEGRAM_BOT_TOKEN` / `EXIST_TELEGRAM_CHAT_ID` do not exist. The Telegram bot quest's
  own routines keep their credentials file under `automation/secrets/telegram/`.
- **Search is one switch.** `EXIST_IS_AI_QMD=true` turns search on in code-server
  (see `019-search-your-notes.md`); `EXIST_SEARCH_MCP_URL` does not exist.
- **The backup destination is set where the remotes are.** `./existential.sh run rclone`
  ends by asking for `EXIST_BACKUP_RCLONE_REMOTE`; `run backup-config` does not exist, and
  every message that named it names `run rclone`.
- **A template default is a literal.** `# DEFAULT: <value>` above an `EXIST_CLI` line is the
  only default form; `# DEFAULT_FROM:` does not exist.
- **`existential.sh` has one path per action.**
  - `./existential.sh test <name>` runs `src/test/unit/test-<name>.sh` or
    `src/test/integration/test-<name>.sh` when one exists, else that service's
    `exist.test.sh`. No suite names are listed by hand.
  - The bare command and `quest` share one render-and-build sequence.
  - `reset` is reached only as `./existential.sh reset`, which offers to stop the stack
    first; it is not listed or runnable as a `run` utility.
  - Unknown flags are unknown actions; `--help`, `-h` and `help` print the usage, which
    lists exactly the actions above.

## Constraints

- An existing `.env.shared` that still holds a removed key keeps working: the key is
  ignored, never an error.
- Rendered files are never re-rendered; the same removals are applied to a rendered copy
  that exists.
- No service changes behaviour other than losing the removed alternative.

## Acceptance Criteria

- **Given** the repo
  **When** `git grep` runs for `EXIST_PEER_HOST_IP`, `EXIST_NETWORK_EXTERNAL`,
  `EXIST_DOCKER_NETWORK_SUBNET`, `EXIST_NFS_SERVER_ADDRESS`, `EXIST_NFS_BASE_PATH`,
  `EXIST_NTFY_TOKEN`, `EXIST_NTFY_TOPICS`, `EXIST_TELEGRAM_`, `EXIST_SEARCH_MCP_URL`,
  `DEFAULT_FROM`, `frontdoor`, `network create`, `run backup-config` or `run ntfy setup`
  outside `graveyard/` and `.decree/applied/`
  **Then** nothing is found
- **Given** any enabled services
  **When** `docker-compose.yml` is generated
  **Then** its `exist` network is `driver: bridge` and not `external`
- **Given** a unit suite `src/test/unit/test-<name>.sh`
  **When** `./existential.sh test <name>` runs
  **Then** that suite runs
- **Given** `./existential.sh run`
  **When** it lists the actions
  **Then** neither `reset` nor `backup-config` is among the utilities
