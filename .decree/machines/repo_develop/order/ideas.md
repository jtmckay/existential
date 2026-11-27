---
machine: repo_develop
---
# Ideas that get followed up

## Overview

A folder of projects started on a clear night and never picked up. The note the person meant
to come back to gets the part done that doesn't need them, so what comes back is a decision.

## Outcome

- `note_triage` asks the model one yes/no question per new or changed note in
  `workspace/notes/` (`TRIAGE_CRITERIA`, one sentence, starting as *a business idea*), and hands
  the ones that pass to its routine. `TRIAGE_DRY_RUN` says what it would pick; the first run
  marks what exists as seen, and `TRIAGE_BOOTSTRAP=true` judges the backlog once.
- `note_develop` drafts what can be done without the author (who else does this, what they
  charge, a draft plan) into `workspace/ai/note-develop/`, under the note's own path, ending with
  the questions only the author can answer. It searches the web through Firecrawl.
- `idea_workup` fans one flagged idea out to the research and sales departments as three
  `agent_task` questions.
- `agent_handoff` hands a file that meets its `CRITERIA` to an agent; the answer lands in
  `workspace/ai/`.
- Guide: *Ideas That Get Followed Up*; Technical: *Worked Example: Note → Action*.

## Constraints

- Notes are read-only to every run: nothing here changes a note.
- Off by default: each call costs model time.

## Acceptance Criteria

- **Given** `./existential.sh test automations`
  **Then** it exits 0
- **Given** `./existential.sh validate conventions`
  **Then** it passes
