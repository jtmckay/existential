---
machine: repo_develop
---
# Every automation is a plugin; each decree project keeps its own list of what is on

## Overview

Repeatable work is a decree machine, not host cron or a one-off `docker exec`. The stack ships
many machines and a person wants few of them, so the repository is every plugin there is and
none of it is on: what is on is each project's own list, and the code has one unit (the
plugin) and one switch per project.

## Outcome

- **One decree image, three projects.** The decree image (decree 0.6) runs two daemons in
  containers and one on the host:
  - `automation` runs `workspace/.decree`: everything that reasons, routes or reaches a
    service API, and every order file. It mounts none of the repo but `automation/.env` and
    `/secrets`, and `workspace/notes/` read-only.
  - `automation-backup` (off by default, not Core) runs `services/automation-backup/`, mounts
    `volumes/` wholesale and the repo read-only, takes the master `.env`, and makes no AI
    call. `/repo` is mounted nowhere else.
  - The host's project is the repo's own `.decree`, run by a decree daemon on the host,
    untouched by `./existential.sh` until something is on in its list.
- **A plugin is a file.** `automation/plugins/<name>.md` is one decree plugin file (`name`,
  `extends`, `machine`, `scripts`, `cron`, `state`, `order`, `needs`) with existential's own
  keys as `x-exist-<key>` (`lib`, `handlers`, `endpoints`, `when`, `topic`, `examples`), and
  `x-exist-project: automation|backup|host` (or a list) says which project runs it. One with no
  machine is lib other plugins need. decree's official `decree_*` plugins are never edited: a
  plugin here `extends:` one under its own name and holds only what it changes.
  `automation/lib/` is only the plugin system's own code.
- **What is on is each project's `.decree/plugins/.on`**, never committed. A new project
  starts with `PLUGIN_DEFAULTS` (`note_watch`, `reconcile`, `service_health`, `pi`,
  `file_advise`, `you_were_here`); the kernel (`notify`, `decree_prune`, and `skill` in the
  workspace) is installed whatever is on. Everything else ships off.
- **`./existential.sh plugin [list|on|off|sync|export]`** (`src/plugins.sh`): `on`/`off`
  edit the list of each project the plugin is tagged for and sync it at once; the sync writes
  what is listed and all it `needs:` into `.decree/plugins/`, `decree install`s it, and removes
  a repo plugin nothing listed needs. `list` marks `on`, `+` (needed by something on) or off.
  `export` writes an installed plugin back to its file from the most privileged project that
  runs it (host, backup, automation). `service on` is a separate step: nothing turns a service
  on for a plugin.
- **The tag is a wall.** A project never installs a plugin not tagged for it, and nothing the
  workspace can write changes what backup or the host runs.
- **What is yours is kept.** A plugin's `state:` is written once to
  `workspace/.decree/store/<plugin>/` and never overwritten; its cron files are installed once
  and are then the project's to edit; `off` deletes neither. A plugin file in
  `workspace/.decree/plugins/` whose name is not the repo's is the person's own, installed
  with `decree install` and never touched by the sync. What the stack builds on its own is an
  offer in `workspace/ai/proposed/`, installed only when a person moves it.
- **Order files are setup that runs once**, by decree's `decree_order` at the daemon's start,
  each waiting on its service, and again only when edited.
- **Backups are three plugins** (`volume_backup`, `db_backup`, `sqlite_backup`) in
  automation-backup, each with one nightly and one weekly cron file listing every service it
  knows; one that is off is skipped. The destination is `EXIST_BACKUP_RCLONE_REMOTE`, which
  `./existential.sh run rclone` asks for at its end.
- **An older install keeps what it had**: `_plugins_on` (`src/utils/migrate.sh`) makes each
  project's `.on` from what its last sync wrote, moves the cron files a flow installed to the
  machine each names, and archives `automation/plugins.yml`.

## Constraints

- The host plugin sync is host code: bash 3.2 and BSD tools.
- A plugin turns on its own automations: every machine its cron and order files name is
  itself or something it needs. A host plugin carries no order files.
- Every notification names its ntfy topic, one of the Topics table on the ntfy docs page.

## Acceptance Criteria

- **Given** a new workspace project
  **When** its first sync runs
  **Then** `.decree/plugins/.on` lists the defaults and each is installed
- **Given** `./existential.sh plugin on newsletter`
  **Then** `newsletter`, its cron file and what it needs are installed, and `plugin off
  newsletter` removes them and leaves its store
- **Given** `./existential.sh test decree`
  **Then** `decree check` passes on each project with every plugin tagged for it, and on each
  plugin alone with only its `needs:`
- **Given** the repo
  **When** it is searched for `existential.sh flow`, `plugins.yml` or `plugins/flows`
  **Then** only `archive/`, the migration and the `.decree/` history mention them
