---
cron: "*/15 * * * *"
routine: clean-runs
---

Keep only the 10 most recent run directories per group, where the group comes from
the run directory's own name — so this covers every run in the shared runs/ dir, not
just the ones this daemon's cron/ happens to list: the other daemon's crons
(triage), webhook-minted runs (file-router), and triggers whose service was
renamed away. Set `keep:` to change the count.

Full routine.log and message.md content goes to Loki and is kept 30 days, so this
prunes a local copy, not the history — Grafana's decree dashboards read Loki.

Runs every 15 minutes, not daily. "Keep 10" is a bound on what is on disk, and a
daily sweep only made it true for one instant a day: triage fires every 5
minutes, so by evening the directory held 96 triage runs — the sweep itself was working (its last pass removed 405),
it just ran 1/144th as often as the thing it cleans up after.

At this interval the real bound is ~10 + one interval of production: ~13 for
triage. The routine is a find plus rm over a few hundred
directories and takes 0s, and its own runs are pruned by the same rule.
