---
cron: "0 * * * *"
routine: note-triage
TRIAGE_CRITERIA: "a business idea — something the author could plausibly build, sell, or start"
TRIAGE_ROUTINE: note-develop
TRIAGE_MAX_NOTES: "20"
---

Hourly scan of the notes vault for new or changed notes worth acting on.

The first run records the vault as seen WITHOUT triaging, so enabling this on an
existing vault does not fire a model call per note. To scan the backlog once, run
it by hand with TRIAGE_BOOTSTRAP=true:

  docker exec decree decree run --routine note-triage --param TRIAGE_BOOTSTRAP=true

TRIAGE_CRITERIA is the part worth rewriting — it is the whole judgment. Try
TRIAGE_DRY_RUN=true for a few runs to see what it would have flagged before it
starts chaining work.

Requires the 'notes' routine (or some other job) to be populating /data/notes.
