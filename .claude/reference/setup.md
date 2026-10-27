# Setup: render, reset, flows, e2e

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
(`EXIST_VRAM_GB`, the per-role endpoint keys) survive an upgrade.

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

The first run asks for `EXIST_USERNAME` and `EXIST_PASSWORD` and nothing else. There is no
picker: Core is what `.env.exist.shared` ships on, so the first run builds it.

Core reserves no GPU, so the hardware questions wait. After rendering, a bare run or `flow`
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

## Flows

A flow is a folder in `flows/`: `flow.md` plus the files that switch on its machine
(`cron/*.md` and `migrations/*.md`, copied into `volumes/workspace_data/.decree/`; `examples/`
is for reading). `src/utils/flows.sh` reads it, sourced by `src/flows.sh` (the command),
`e2e.sh` and automation's `exist.initial.sh`. It is awk over flat frontmatter, not yq, because
e2e and `exist.initial.sh` run on the host. The keys are documented in its header; keep the
frontmatter flat (scalars, block lists of plain values) or the reader will not see it.

`flow on <name>` turns on the flows it needs (`flows:`, depth first), sets every service flag
they name (`services:`) unless the GPU answer forbids one (`vendor_forbids_service`: a local
ollama under `external`), copies each file not already in place (a migration already in
`processed.md` counts as in place), and prints the body: only what is left for a person. Then
`existential.sh` renders and builds. `flow off` deletes only copies identical to the flow's
file, never touches services, and names a `default: true` flow in `.decree/flows-off`, which
`exist.initial.sh` reads before re-activating the defaults. `src/flows.sh` exits 3 for "nothing
changed" (a list, an empty pick), which skips the rebuild.

Every flow is in the table on `site/docs/flows/index.md`, and its names resolve (`validate
conventions`). The setup steps for a service no flow needs live on the service's docs page.

## e2e

e2e answers one question — **does a fresh install come up working?** — because that is the one
thing `triage` cannot see.

It runs Core (the install as it ships), then every flow marked `e2e: true` over it, or the units a
pattern names (`./existential.sh e2e search`). It copies the **working tree** (not HEAD) into a
throwaway clone → render → up → checks → down, and does *not* re-run per-service tests.

**An e2e check is a markdown file in `src/test/e2e/checks/`** — a decree message, dropped into
the right daemon's inbox once the stack is up and its migrations have finished.
Adding a check is adding a file. Contract: `src/test/e2e/checks/README.md`.

Every run's evidence — `results.md`, each run's `message.md`, `events.jsonl` and script logs,
and unhealthy containers' logs — is copied to `e2e-out/<stamp>-<unit>/` before teardown.
Gitignored, and written even when a run crashes.
