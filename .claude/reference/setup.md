# Setup: render, reset, quest, e2e

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

## Quest

`quest` launches the interactive picker first.

On a **first run** — nothing enabled beyond the shipped defaults, which `_has_any_enabled`
checks against `.env.exist.shared` rather than by counting `true`s — quest asks two hardware
questions and then leads with a single **Core, or no thanks** choice (`src/quests/00-core.md`)
instead of forty service checkboxes. Declining falls through to the full picker.

The hardware questions are **GPU vendor first** (`src/utils/gpu-vendor.sh` →
`EXIST_GPU_VENDOR`), then VRAM (`src/utils/model-tiers.sh` → `EXIST_VRAM_GB`). Answering
*No GPU* sets `EXIST_VRAM_GB=0` itself and **skips** the VRAM question, so the VRAM picker is
always asked with `--gpu-only`. `EXIST_GPU_VENDOR` records that the pair was asked, so they are
never re-asked; `./existential.sh run models` is the way back and re-asks both. The VRAM picker's
last entry takes a model name instead of a number (`custom:<tag>`) — see
`.claude/reference/models.md`.

### Quest file format

A quest is a markdown file in `src/quests/`: YAML frontmatter for the data (`name`, `tagline`,
`e2e`, `services`, `done`, and — Core only — `copies`), the body for the guide — the same shape
as decree's cron and migration files.

It is read by `yq` in `quest.sh` (`qmeta` / `qbody`), **not** by decree, so decree's "extra keys
become env vars" contract does not apply here. Everything that reads a quest must scope itself
to the frontmatter; the body is free-form prose.

### The two kinds of quest

**Numbered = Core, one slice at a time.** `00-core.md` is the whole system in one pass;
`01`–`06` are exactly a *partition* of it — every Core service and every Core `copies:` entry
belongs to exactly one of them, and to no two. Adding a service to Core means adding it to the
slice that owns it. e2e only ever runs numbered quests (`[0-9][0-9]-*.md`), which is the other
reason the numbered range is the product and not a catalogue.

**Unnumbered = everything past Core.** One file per integration or automation, no prefix, no
ordering.

Only `00-core.md` uses `copies:` to auto-activate templates; that is deliberate, since Core IS
the base system and should ask as little as possible. **Every other quest — the numbered slices
included — writes nothing.** Its activation steps (`mkdir`/`cp`/`docker compose restart`) go in
its guide body, to be read and typed. The point past Core is for the user (or an agent driving
this repo) to see and understand the cron.example/ → cron/ mechanism rather than have a picker
do it invisibly, so these files are documentation and training as much as setup.

### `done:` — crossing a quest off

`quest_done` marks a quest finished when its services are enabled **and** it can point at proof
on disk. A quest must SAY how it is finished, one of two ways:

- `copies:` (Core only) — done when no destination is still pending.
- `done.files` — paths, relative to the repo, that its guide told you to create.
  `done.env` — `.env.shared` keys its guide told you to fill in; non-blank is done.

**A quest that declares neither is never crossed off.** That asymmetry is the point: several
guides end in work this repo cannot see (a ComfyUI checkpoint, a Spotify OAuth grant, a wake
word trained on a phone), and a wrong ✓ there costs more than a missing ✓ everywhere.

Because 01–06 partition Core, running Core writes every file they name and all six cross
themselves off with no knowledge of each other.

`quest_skips_service` is the one exception to "enabled": a service the GPU-vendor answer forbids
(local ollama under `EXIST_GPU_VENDOR=external`) is not missing, it is refused — the same rule
`_enable_quest_services` applies on the way in.

## e2e

e2e answers one question — **does a fresh install come up working?** — because that is the one
thing `triage` cannot see.

It copies the **working tree** (not HEAD) into a throwaway clone → render → up → checks → down,
and does *not* re-run per-service tests.

**An e2e check is a markdown file in `src/test/e2e/checks/`** — a decree migration, copied into
the clone and numbered `90-` and up so the product's own migrations are all graded first.
Adding a check is adding a file. Contract: `src/test/e2e/checks/README.md`.

Every run's evidence — `results.md`, each check's `routine.log` and `run.json`, dead letters,
and unhealthy containers' logs — is copied to `e2e-out/<stamp>-<quest>/` before teardown.
Gitignored, and written even when a run crashes.
