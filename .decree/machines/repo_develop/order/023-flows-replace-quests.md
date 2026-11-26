---
machine: repo_develop
---
# A flow is a page, a plugin is the unit, and each project keeps its own list of what is on

## Overview

Quests were service groups with a guide to read and type; flows replaced them, then grew into a
second kind of plugin (no machine, a title, the services to ask for, cron and order files of
other plugins), a picker, an on-list for every project and an awk reader for the host. All of it
said what the plugins and services already say. What a person wants is still the thing the stack
does for them ("my own newsletter", "transcribe my voice memos"): that is written down, once, as
a recipe; the code has one unit, the plugin, and one switch per project.

## Outcome

- **`automation/plugins/` is every plugin there is, and none of it is on.** A plugin carries
  its own cron and order files (the machine they run is itself or something it `needs:`), and
  one with no machine is lib other plugins need. There is no `automation/plugins/flows/`.
- **What is on is each decree project's own list**, `.decree/plugins/.on`: the workspace's,
  automation-backup's and the repo's own `.decree`. A new project starts with
  `PLUGIN_DEFAULTS` (`note_watch`, `reconcile`, `service_health`, `pi`, `file_advise`,
  `you_were_here`); `notify`, `decree_prune` and, in the workspace, `skill` are installed
  whatever is on. There is no `automation/plugins.yml` and no `plugins.exist.yml`.
- **`./existential.sh plugin [list|on|off|sync|export]`** (`src/plugins.sh`): `on`/`off` edit
  the list of each project the plugin is tagged for and sync it at once; the sync installs what
  is listed and all it needs and removes a repo plugin nothing listed needs. `service on|off`
  turns services on; nothing turns a service on for a plugin.
- **A flow is a row on `site/docs/flows/index.md`**: what it does, its `service on` and
  `plugin on` lines, and what is left for a person. There is no `./existential.sh flow`.
- **Backups are three plugins** (`volume_backup`, `db_backup`, `sqlite_backup`), each with one
  nightly and one weekly cron file listing every service it knows; one that is off is skipped.
- **e2e runs Core**, as it ships.
- **An older install keeps what it had**: `_plugins_on` (`src/utils/migrate.sh`) makes each
  project's `.on` from what its last sync wrote, moves the cron files a flow installed to the
  machine each names, and archives `automation/plugins.yml`.

## Constraints

- The host plugin sync is host code: bash 3.2 and BSD tools (`./existential.sh test host`).
- A project never installs a plugin not tagged for it, and nothing the workspace can write
  changes backup's or the host's list.
- `validate conventions` fails a docs `plugin on`/`service on` line that names nothing, and a
  plugin a person turns on (a machine nothing needs) with no line on the Flows page.

## Acceptance Criteria

- **Given** a fresh checkout
  **When** `./existential.sh validate conventions` and `./existential.sh test` run
  **Then** both exit 0
- **Given** a new workspace project
  **When** its first sync runs
  **Then** `.decree/plugins/.on` lists the defaults and each is installed
- **Given** `./existential.sh plugin on newsletter`
  **Then** `newsletter`, its cron file and what it needs are installed, and `plugin off
  newsletter` removes them and leaves its store
- **Given** an install whose sync wrote `.decree/plugins/.existential`
  **When** `./existential.sh` runs
  **Then** each project's `.on` names what it had, under its plugin's name
- **Given** the repo
  **When** it is searched for `existential.sh flow`, `plugins.yml` or `plugins/flows`
  **Then** only `archive/`, the migration and the `.decree/` history mention them
