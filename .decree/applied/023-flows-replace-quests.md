---
machine: develop
---
# A flow is a folder: turn one on and it brings the services it needs

## Overview

Quests were service groups with a guide to read and type: 28 files, a 944-line picker, and a
second list of what the stack can do beside the curated machines in `automation-examples/`.
What a person wants is the thing the stack does for them ("my own newsletter", "transcribe my
voice memos"), and the machine that does it already knows which services it needs. So the
curated machines become the unit you pick, each bringing whatever has to be on first. This
is not a marketplace: the flows ship in the repo, with nothing to download.

## Outcome

- **`flows/<name>/` is one flow**: `flow.md` (frontmatter `name`, `tagline`, `docs`, and
  block lists `services` of `EXIST_IS_*` flags, `flows` it needs, `processors` it copies from
  `automation/lib/file-processors.example/`; scalars `default` and `e2e`; then a body of only
  what is left for a person), plus `cron/*.md` and `migrations/*.md` that switch its machine on,
  and `examples/` messages that are never copied. Every template that was in
  `automation-examples/` is in exactly one flow; that folder and `src/quests/` are gone.
- **`./existential.sh flow`**: a picker in a terminal, a list otherwise; `flow list`, `flow on
  <name>...`, `flow off <name>...`. On turns on the flows it needs first, sets each service flag
  unless the GPU answer forbids that service, copies each file not already in place (a
  migration in `processed.md` counts), prints the body, then renders and builds. Off deletes only
  copies identical to the flow's file, says so for an edited one, leaves services alone, and
  records a default flow in `workspace/.decree/flows-off`. A list or an empty pick rebuilds nothing.
- **Core ships on.** `.env.exist.shared` has code-server, automation and ntfy `true`. The first
  bare `./existential.sh` asks the two hardware questions through `run models` (which also asks
  for the model server's URL when the models live elsewhere) and builds Core; no picker.
- **Default flows** (`default: true`): `you-were-here`, `look-back`, `clean-runs`,
  `health-checks`. automation's `exist.initial.sh` activates each missing file of every default
  flow not named in `flows-off`. They need nothing beyond Core.
- **e2e** runs Core as it ships, then each flow with `e2e: true` over Core (its services, the
  flows it needs, their files).
- **Docs** describe it: Getting Started's setup is `./existential.sh` then `flow`; the Flows
  page has a table with a row per flow; a service no flow needs is a flag, its setup on its own
  page (Caddy's CA and hostnames, ntfy's subscribe, NFS mounting on Storage, backups on rclone).
  No page, README, reference or comment tells anyone to run `quest` or copy from
  `automation-examples/`.

## Constraints

- `src/utils/flows.sh` reads a manifest with awk, not yq: e2e and `exist.initial.sh` run on the
  host. It honours a `REPO_DIR` it is given.
- Services stay one flag per folder; a flow never renders, creates or deletes a service.
- `validate conventions` checks every flow: it has `flow.md` with a name, tagline and a docs page
  that exists; each service, flow and processor it names exists; it has a row on the Flows page.
- `decree check` (`./existential.sh test decree`) runs with every flow's files queued, and fails
  when two flows ship a file of the same name.

## Acceptance Criteria

- **Given** a fresh checkout
  **When** `./existential.sh validate conventions` and `./existential.sh test` run
  **Then** both exit 0
- **Given** an install with newsletter off
  **When** `./existential.sh flow on newsletter`
  **Then** `volumes/workspace_data/.decree/cron/newsletter.md` matches `flows/newsletter/cron/newsletter.md`
- **Given** `EXIST_GPU_VENDOR=external`
  **When** `./existential.sh flow on local-models`
  **Then** `EXIST_IS_AI_OLLAMA` stays `false` and the output says why
- **Given** `flow on transcription`
  **Then** WhisperX and Nextcloud are on, nextcloud-capture's migrations are in place, and
  `automation/lib/file-processors/whisperx-transcribe.sh` exists
- **Given** `flow off you-were-here`
  **When** automation's `exist.initial.sh` runs again
  **Then** its cron is not put back
- **Given** the repo
  **When** it is searched for `src/quests`, `quest.sh` or `automation-examples`
  **Then** only `graveyard/`, `archive/` and the `.decree/` history mention them
