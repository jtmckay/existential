---
machine: develop
---
# Write "next time…" in a note, and the stack offers to build that automation

## Overview

People write down how they want something handled next time ("next time I have a business
idea, research who already does it and draft a one-page plan") and then, next time, forget
they wrote it. The stack already reads every note that changes. It should notice a standing
instruction, offer to automate it, build it once accepted, and run it when the event comes,
with results the person can dig into. The offer is a decree migration, the intent and
declarative requirements of the automation, so the person accepts and edits the desired
state in plain words and the stack keeps the built machine in step with it, the way this
repo's own migrations work.

## Outcome

- **On by default, with Core plus a chat model.** The `handlers.yml` seeded into
  `workspace/.decree/` on install runs `note_watch` when a note under `notes/` settles, and
  `reconcile` when a file in `notes/automations/` is created, edited or deleted.
- **Noticing.** `note_watch` makes one model call per settled note. A standing instruction
  (an action on a future event) becomes one `automation_propose` run, once per note and
  name. A note that is the event of an accepted automation with a note trigger starts that
  automation, and only an automation listed in `.decree/automations.yml`. Its own files
  (`notes/automations/`) and the digests are never read. With no model reachable it does
  nothing and the run still succeeds.
- **Proposing.** `automation_propose` writes `notes/automations/proposed/<name>.md`: frontmatter
  `machine: develop`, `automation: <name>`, `from: <note>`, then Overview (the person's own
  words), Outcome (what starts it, what it produces, results in `ai/automations/<name>/` and
  a notification), Constraints and Acceptance Criteria. It contains no code. The person is
  told, with how to accept. A name that is already a machine is never proposed.
- **Accepting.** Moving the file to `notes/automations/<name>.md` makes `reconcile` file it
  as `.decree/migrations/A<UTC stamp>-<name>.md`, which the daemon runs with `develop`.
- **Building.** The workspace's `develop` machine has the chat model answer with a trigger
  (note event, file glob, or cron schedule) and a `steps` function, and writes the machine
  and script from fixed templates (`automation/lib/automations/run.sh` is the frame every
  built script sources) and the trigger: a `note` entry `note_watch` matches against, a
  `handlers.yml` entry, or `.decree/cron/<name>.md`. It records the built-from migration in
  `.decree/applied/`. The gate is the trigger's rules (a file trigger never matches `ai/`,
  `.decree/` or `notes/automations/`), a `steps` function that parses, and `decree check`; a
  failed gate is undone, and the second attempt is given the errors.
- **Running.** A built automation writes its results to
  `ai/automations/<name>/<date>-<note>.md`, linked to the note or file that started it, and
  sends their first lines to ntfy.
- **Keeping in step.** Editing an accepted spec updates its migration; once built, a spec
  that differs from `.decree/applied/` runs again, so `develop` rebuilds it. Deleting the spec
  removes the machine, script, trigger, registry entry and migration.
- **Documented.** `site/docs/flows/note-to-automation.md` explains the flow, the proposal as a
  migration, editing and removing, and what a built automation can reach; the tour lists it
  among Core's flows.

## Constraints

- No AI CLI runs in the `automation` container: the workspace's `develop` builds through
  `automation/lib/model.sh`.
- Only a machine listed in `.decree/automations.yml` is ever replaced or removed; a name decree
  ships or the person wrote is refused.
- The model writes only `steps` and the trigger; the machine file and the frame are templates.

## Acceptance Criteria

- **Given** a note "next time I have a business idea, research who already does it and draft
  a one-page plan" and a reachable model
  **When** it settles
  **Then** `notes/automations/proposed/<name>.md` holds a `machine: develop` migration with
  Overview, Outcome, Constraints and Acceptance Criteria, and a notification says how to accept it
- **Given** that proposal moved to `notes/automations/`
  **When** the daemon runs its migration
  **Then** `.decree/machines/<name>.yml`, an executable `.decree/scripts/<name>.sh` and its
  trigger exist, and `decree check` passes
- **Given** a built automation with a note trigger
  **When** a later note that is its event settles
  **Then** it runs and writes `ai/automations/<name>/<date>-<note>.md`
- **Given** a spec whose name is an existing shipped machine
  **When** it is accepted
  **Then** nothing is built and that machine is unchanged
- **Given** `./existential.sh test automations`
  **Then** it exits 0
