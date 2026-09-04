---
cron: "0 * * * *"
routine: note-triage
TRIAGE_CRITERIA: "a business idea — something the author could plausibly build, sell, or start"
TRIAGE_ROUTINE: note-develop
TRIAGE_MAX_NOTES: "20"
# Swap the work: idea-workup fans the idea out to the research and sales departments
# instead of drafting one document. Needs idea-workup and hermes-dept enabled.
# TRIAGE_ROUTINE: idea-workup
# TRIAGE_LEDGER: "false"   # chain every pass, even an idea already evaluated
# TRIAGE_LEDGER_MAX: "100" # how many past ideas the "is it new?" call sees
---

Hourly scan of the notes vault for new or changed notes worth acting on.

The first run records the vault as seen WITHOUT triaging, so enabling this on an
existing vault does not fire a model call per note. To scan the backlog once, run
it by hand with TRIAGE_BOOTSTRAP=true:

  printf -- '---\nroutine: note-triage\nTRIAGE_BOOTSTRAP: true\n---\n' > automation/inbox/bootstrap.md

TRIAGE_CRITERIA is the part worth rewriting — it is the whole judgment. Try
TRIAGE_DRY_RUN=true for a few runs to see what it would have flagged before it
starts chaining work. A dry run never writes to the ledger, so tuning the
criteria does not poison the "is this new?" check.

An idea that passes is checked against the ideas already evaluated before
anything is chained — writing the same thought down twice gets you one workup,
not two.

Requires the 'notes' routine (or some other job) to be populating /data/notes.
