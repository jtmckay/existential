# Setup: render, reset, plugins, e2e

The mechanics behind `./existential.sh`. The rules are in `CLAUDE.md`; this is how they work.

## Rendering

`./existential.sh` renders `*.exist.*` templates, runs each enabled service's
`exist.initial.sh`, and merges enabled services into a unified `docker-compose.yml`. Disabled
services are skipped entirely — no secrets or templates land on disk for a service that is off.

A rendered destination is written **once** and skipped thereafter. There is no re-render flag.

The one exception is key-level, not file-level. A rendered `.env*` is still never overwritten,
but every run appends keys the template has gained since (`_reconcile_env_keys` in
`src/templates.sh`), so `git pull && ./existential.sh` reaches an existing install instead of
silently leaving it a version behind. It is **append-only** — existing values, blanks included,
are never touched. That is what makes the blank-means-not-yet-asked convention
(`EXIST_VRAM_GB`) survive an upgrade.

Images are the other exception:

- **A service `image:`** (`_offer_image_updates` in `existential.sh`, the start of `_build`): each
  enabled service's rendered `image:` is compared with its template's, per service, and the
  differences are listed and rewritten on yes. No terminal (the `pull_existential` plugin, which is
  opt-in): rewritten without asking. This is how `run check-versions --update` reaches an install.
- **The decree image** (`ensure_adhoc_built` in `src/utils/adhoc.sh`): built with the
  `exist.context` label, a checksum of the files `.dockerignore` lets in. A mismatch rebuilds it.
  e2e stamps its build the same way, since it shares the tag.
- **Staging** (`_stage_images`, the end of `_build`): `docker compose pull --ignore-buildable`,
  then `build` when a service has `build:`. Neither touches a running container; compose swaps
  them only on `up`. A failed pull (offline) is reported, not fatal.

## `archive/`

Two different things live here, in two clearly separated shapes:

| Path | Written by | When |
|---|---|---|
| `archive/<timestamp>/` | `reset` | once per reset, holding every rendered file with its paths preserved |
| `archive/docker-compose/` | `generate-compose.ts` | the previous root `docker-compose.yml`, rotated on **every** run, last 3 kept |

The compose rotations used to sit loose at the top of `archive/` next to the reset directories,
which made a listing read as one muddle — nothing distinguished "a whole install, archived once"
from "the previous compose file, rotated a minute ago". `generate-compose.ts` moves any loose
ones into the subdirectory on its next run, so an existing install tidies itself.

`src/test/unit/test-compose.sh` pins both halves: archives land in the subdirectory, and none
are loose in `archive/` or in the repo root.

## `reset`

Archives every rendered file to `archive/<timestamp>/`, paths preserved and gitignored, so the
next run renders fresh. Restore with `cp -r archive/<stamp>/. .`.

It never touches `volumes/` beyond offering to delete the `*_cache` ones.

Because it archives the generated root `docker-compose.yml` too, it first offers to
`docker compose down` a stack that is still up. That offer is host-side: `reset` itself runs in
the adhoc container, which has no docker socket.

## The first run

The first run, with a terminal and an engine, asks one question (`_ask_role`): **a)** Core, the
default, or **b)** a worker. **a)** is Core, what `.env.exist.shared` ships on
(code-server, ntfy, automation, qmd, Firecrawl); `templates.sh`'s `_ask_login` asks the login
the moment `.env.shared` is made, before any service renders it (Enter keeps
`EXIST_USERNAME=admin` and the generated `EXIST_PASSWORD`; a typed password is asked twice,
unseen, 8+ of `A-Za-z0-9._-`), and nothing else: no Loki, Grafana or model gateway. A
controller is never made by setup, only by `run fleet controller`, by choice. **b)** goes straight
to `_worker_without_engine`, which writes the answers (`EXIST_HOST_ROLE=worker`,
`EXIST_CONTROLLER`) before it checks a tool. The first answer is `.env.role` until
`.env.shared` exists, then `EXIST_HOST_ROLE` (`_record_role`). A missing tool is offered (`_offer_install`: `_install_cmd` per tool, shown, Enter
runs; sudo only for a package manager, on that yes), and `_host_plugins` offers to start the
host daemon now and at every boot (`src/lib/host-daemon.sh install`: a systemd user unit,
`existential-host.service`, enabled with linger, or a LaunchAgent; `status`, `uninstall`). A
worker's run ends with `_worker_summary`: controller, alloy, daemon, boot, last report. With no terminal nothing is asked:
Core as it ships, `admin` and a generated password. `_report_login` prints the login once and
`_report_model` says every run that there is no model until `EXIST_MODEL_URL` is set. Later,
`run fleet controller` and `run fleet join <controller>` do either by hand. With every
`EXIST_IS_*` false, `_build` stops at "nothing is on yet". A worker is any host whose host project has `report_host` on
(`.decree/plugins/.on`, `_is_worker`), and the controller is the worker with no `EXIST_CONTROLLER` (`_is_controller`).
A host with neither docker nor podman (`adhoc_find_runtime` fails), and
one that is already a worker with no service on (`_worker_only`) all skip adhoc altogether, on
the bare run and `plugin` alike (a tool missing is named, never a reason to build):
`_worker_without_engine` checks decree, yq, curl and tmux (`_worker_needs`, each missing one
printed with `_install_steps`), writes `.env.shared` as every `EXIST_IS_*=false` plus
`EXIST_CONTROLLER` (a later run with an engine appends the rest of the keys, rendered), puts
`report_host` in the host project's list, and runs `_build`, whose `_host_plugins` runs `src/plugins.sh sync host` on the
host when `DOCKER_CMD` is unset. So that sync, and the plugin library it sources, is host code:
bash 3.2 and BSD tools, covered by `test host` when yq and decree are installed. **Everything between hosts and the controller is HTTPS through the controller's Caddy**, on
any network: `EXIST_CONTROLLER` is the controller's domain (its `EXIST_DOMAIN`, never an
address, which `report_host`, `fleet join` and `_worker_summary` refuse), and every address is
derived from it, with nothing to ask the controller: reports, runs (alloy), offers,
notifications, models and `fleet_gpu.md` at `https://model-gateway.<domain>`, and a service
off here at `https://<slug>.<domain>` (`resolveOffServices`). Caddy hands that name to the
model gateway, which has no host port
and passes only Loki's push, query_range, labels and buildinfo (`/ready` open), behind the
fleet secret (a header from a file or stdin, never argv), since offers in that Loki decide where
hosts send calls and the secret. Loki has no login and stays on loopback (`LOKI_BIND`
`127.0.0.1`), where the controller's own `report_host` and `peers` reach it. A plugin with
`x-exist-project: host` (`report_host`, `pull_existential`) is on in the host project's own list and installed into the repo's `.decree`; `_host_plugins` leaves that project alone until its list names something. `EXIST_EMAIL` is asked by `_ask_if_needed` before the first enabled service that uses it
renders; Core uses none.

Core reserves no GPU, so the hardware questions wait. After rendering, a bare run or `service`
(with `EXIST_GPU_VENDOR` blank and a terminal) runs `src/lib/models.sh` with `FIRST_RUN=1`
only when an enabled service's template declares `driver: nvidia`
(`_ask_hardware_if_needed`). Until then blank resolves to `none`.

The hardware questions are **GPU vendor first** (`src/utils/gpu-vendor.sh` →
`EXIST_GPU_VENDOR`), then VRAM (`src/utils/model-tiers.sh` → `EXIST_VRAM_GB`). Answering
*No GPU* sets `EXIST_VRAM_GB=0` itself and **skips** the VRAM question, so the VRAM picker is
always asked with `--gpu-only`; *models live elsewhere* (`external`) asks for `EXIST_MODEL_URL`
first. `EXIST_GPU_VENDOR` records that the pair was asked, so they are never re-asked;
`./existential.sh run models` is the way back and re-asks both. The VRAM picker's last entry
takes a model name instead of a number (`custom:<tag>`) — see `.claude/reference/models.md`.

## Plugins

Nothing in `automation/plugins/` is on. What a decree project has on is its own
`.decree/plugins/.on` (the workspace's, `services/automation-backup/plugins/.on`, the repo's
`.decree/plugins/.on`), seeded with `PLUGIN_DEFAULTS` the first time (`plugin_seed`).
`./existential.sh plugin on|off <name>` (`src/plugins.sh`) edits the list of each project the
plugin's `x-exist-project` names, skipping backup while automation-backup is off, and syncs each
at once (`plugin_sync`, `automation/lib/plugin.sh`): what is listed and all it needs is written
into `.decree/plugins/`, a repo plugin nothing listed needs is removed, and `decree install`
installs it. `plugin` runs in adhoc, or on the host with the host's yq and decree where there
is no engine or the host is a worker only. It exits 3 for "nothing changed" (`list`).
`service [list|on|off]` (`src/services.sh`) turns one service's `EXIST_IS_*` flag on or off,
skips one the GPU answer forbids (`vendor_forbids_service`), and rebuilds; it exits 3 the same way.

A flow is not code: it is a section of a Guide page in `site/docs/flows/` (one page per
problem), the `service on` and `plugin on` lines for one job and what is left for a person.
`validate conventions` fails a `plugin on` or `service on` line in the docs that names nothing,
and a plugin a person turns on (a machine nothing needs) whose `plugin on` line is on no docs
page (a host or multi-host plugin's line can live on its hosting page). The setup steps for a service on its own live on the
service's docs page.

## e2e

e2e answers one question — **does a fresh install come up working?** — because that is the one
thing `triage` cannot see.

It runs Core, the install as it ships. It copies the **working tree** (not HEAD) into a
throwaway clone → render → up → checks → down, and does *not* re-run per-service tests.

**An e2e check is a markdown file in `src/test/e2e/checks/`** — a decree message, dropped into
the right daemon's inbox once the stack is up and its migrations have finished.
Adding a check is adding a file. Contract: `src/test/e2e/checks/README.md`.

Every run's evidence — `results.md`, each run's `message.md`, `events.jsonl` and script logs,
and unhealthy containers' logs — is copied to `e2e-out/<stamp>-<unit>/` before teardown.
Gitignored, and written even when a run crashes.
