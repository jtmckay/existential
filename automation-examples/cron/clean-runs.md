---
cron: "0 10 * * *"
routine: clean-runs
---

Keep only the 10 most recent run directories per group, where the group comes from
the run directory's own name — so this covers every run in the shared runs/ dir, not
just the ones this daemon's cron/ happens to list: the other daemon's crons
(workspace-sync), webhook-minted runs (s3-router), and triggers whose service was
renamed away. Set `keep:` to change the count.

Full routine.log and message.md content goes to Loki and is kept 30 days, so this
prunes a local copy, not the history — Grafana's decree dashboards read Loki.
