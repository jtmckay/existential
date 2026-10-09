---
cron: "0 * * * *"
machine: note_triage
params:
  TRIAGE_CRITERIA: "a business idea — something the author could plausibly build, sell, or start"
  TRIAGE_ROUTINE: note_develop
  TRIAGE_MAX_NOTES: 20
  # Swap the work: idea_workup fans the idea out to the research and sales
  # departments instead of drafting one document.
  # TRIAGE_ROUTINE: idea_workup
  # TRIAGE_LEDGER: false   # hand off every pass, even an idea already evaluated
---

Hourly scan of the notes vault for new or changed notes worth acting on.

The first run records the vault as seen WITHOUT triaging, so enabling this on an
existing vault does not fire a model call per note. To scan the backlog once, run
it by hand with TRIAGE_BOOTSTRAP=true:

  docker exec automation decree emit --machine note_triage --param TRIAGE_BOOTSTRAP=true </dev/null

TRIAGE_CRITERIA is the part worth rewriting — it is the whole judgment. Try
TRIAGE_DRY_RUN=true for a few runs to see what it would have flagged before it
starts handing off work. A dry run never writes to the ledger, so tuning the
criteria does not poison the "is this new?" check.

An idea that passes is checked against the ideas already evaluated before
anything is handed off — writing the same thought down twice gets you one workup,
not two.

Requires the 'notes' machine (or some other job) to be populating /data/notes.
