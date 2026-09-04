---
cron: "0 * * * *"
routine: routines-snapshot
---

Refreshes `workspace/ai/decree-routines.md` every hour: the name, description,
and parameters of every currently-enabled decree routine, pulled straight from
`decree routine` — no separate list to keep in sync by hand.

Hermes/OpenCode has no mount into `automation/`, so this file is how it learns
what's runnable and what to put in a message's frontmatter to run it. It lands
in `workspace/ai/`, the same directory `agent-task` writes to — indexed by
OpenViking, excluded from `workspace-sync`, so it's searchable but can't
trigger another run.

The file is overwritten in place each run, not versioned. Enable/disable a
routine in `services/automation/decree/config.exist.yml` (or its rendered
`config.yml`) and the next run picks it up.

Copy to automation/cron/ and restart automation to activate. To generate the
first snapshot immediately instead of waiting for the top of the hour, drop a
bare `routine: routines-snapshot` message in `automation/inbox/` by hand.
