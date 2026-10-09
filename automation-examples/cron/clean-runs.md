---
cron: "0 4 * * *"
machine: clean_runs
params:
  OLDER_THAN: 7d
---

Delete this project's finished runs older than OLDER_THAN, once a day.

Every run's events.jsonl and script logs are shipped to Loki and kept 30 days,
so this prunes a local copy, not the history — Grafana's decree dashboards read
Loki. `decree prune` never touches a run that has not finished, a failed
migration, or a child run whose parent is still going.
