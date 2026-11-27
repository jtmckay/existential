---
machine: repo_develop
---
# Write "next time…" in a note, and the stack offers to build that automation

## Overview

People write down how they want something handled next time ("next time I have a business
idea, research who already does it and draft a one-page plan") and then, next time, forget
they wrote it. The stack already reads every note that changes. It should notice a standing
instruction, offer to automate it, build it once accepted, and run it when the event comes. The
offer is a spec in plain words (intent and declarative requirements, the way this repo's own
order files work), so the person accepts and edits the desired state, never code. Nothing it
builds runs until a person installs it.

## Outcome

- **On by default, with Core plus a chat model.** `note_watch` and `reconcile` are default
  plugins; their handlers run `note_watch` when a note under `notes/` settles and `reconcile`
  when a file in `notes/automations/` is created, edited or deleted.
- **Noticing.** `note_watch` makes one model call per settled note. A standing instruction
  becomes one `automation_propose` run, once per note and name. A note that is the event of an
  installed plugin's `x-exist-when` starts that plugin. Its own files (`notes/automations/`)
  and the digests are never read. With no model it does nothing and the run still succeeds.
- **Proposing.** `automation_propose` writes `ai/proposed/<name>.md`, a spec: Overview (the
  person's own words), Outcome (what starts it, what it produces, results in
  `ai/automations/<name>/` and a notification), Constraints and Acceptance Criteria. No code.
  The person is told how to accept. A name that is already a plugin is never proposed.
- **Accepting.** Moving the spec to `notes/automations/<name>.md` makes `reconcile` hand it to
  `develop`. The spec stays the automation's desired state.
- **Building, as an offer.** The workspace's `develop` has Claude (when `agent_ready`) or the
  chat model answer with a trigger (a note event as `x-exist-when`, a file glob as a handler,
  or a cron schedule) and a `steps` function, and writes one plugin file from fixed templates:
  the machine, its script (which sources the frame `lib/automations/run.sh`, `develop`'s
  `x-exist-lib`) and the trigger. It must pass `decree check` in a scratch copy and the
  trigger's rules (a file trigger never matches `ai/`, `.decree/` or `notes/automations/`); a
  failed check goes back to the model once, a second failure reaches the phone. The file goes
  to `ai/proposed/<name>.md`, marked "Built by develop from notes/automations/<name>.md".
  **Nothing is installed.**
- **Installing** is the person's: `mv ai/proposed/<name>.md .decree/plugins/ && decree install
  <name>`, after reading it.
- **Running.** A built automation writes `ai/automations/<name>/<date>-<note>.md`, linked to
  what started it, and sends its first lines to ntfy.
- **The frame** gives `steps` the triggering note or file, `ask` (one chat model answer),
  `web_search <query> [n]` and `web_read <url>` (Firecrawl, no key; when Firecrawl is off,
  steps that use them fail the check), `agent` (only when Claude is signed in; otherwise steps
  that call it fail the check), `curl` and `jq`. Research cites its sources, and a judgement the
  person asked for comes first as `## Verdict`, the section that reaches the phone.
- **Keeping in step.** Editing an accepted spec makes `develop` offer a new version. To remove
  one: `rm .decree/plugins/<name>.md && decree install`; deleting the spec removes nothing.
- **Documented** in the Guide's Tell It Once (what a person writes, moves and gets back, with
  the business-idea research as its example) and the Technical Your Own Plugins, *Built from a
  note* (the machines, the spec, what a built automation can reach). The tour lists it among
  Core's flows, and the business-idea research among the add-ons', on Firecrawl.

## Constraints

- `develop` only ever replaces a plugin it built (marked as above); a name the repo ships or
  the person wrote is refused.
- The model writes only `steps` and the trigger; the machine and the frame are templates.

## Acceptance Criteria

- **Given** a note "next time I have a business idea, research who already does it and draft
  a one-page plan" and a reachable model
  **When** it settles
  **Then** `ai/proposed/<name>.md` holds a spec with Overview, Outcome, Constraints and
  Acceptance Criteria, and a notification says how to accept it
- **Given** that spec moved to `notes/automations/`
  **When** `develop` runs
  **Then** `ai/proposed/<name>.md` is a plugin file that passes `decree check`, and nothing new
  is in `.decree/machines/`
- **Given** Firecrawl disabled and steps that call `web_search`
  **When** `develop` runs
  **Then** the check fails saying Firecrawl is off, and nothing is offered
- **Given** a spec whose name is a plugin the repo ships
  **When** it is accepted
  **Then** nothing is built and that plugin is unchanged
- **Given** `./existential.sh test automations`
  **Then** it exits 0
