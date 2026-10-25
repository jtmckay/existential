---
cron: "0 * * * *"
machine: routines_snapshot
---

Refreshes `workspace/ai/decree/` every hour: `system.md` (every machine, its
description, and what it hands work to — straight from `decree graph`), each
machine's file (the params it takes, with their defaults), and `endpoints.yml`
(automation-webhook's endpoints, including the `/hermes/*` ones hermes may call).

Hermes has no mount into `automation/`, so this is how it learns what decree can
run and how to ask for it. It lands in `workspace/ai/`, the same directory
`agent_task` writes to — indexed by OpenViking, and written straight to disk, so
it is searchable but cannot trigger another run.

`./existential.sh flow on hermes-knows-decree` activates it. To refresh it now:

  docker exec automation decree emit --machine routines_snapshot </dev/null
