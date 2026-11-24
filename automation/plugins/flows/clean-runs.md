---
name: clean-runs
x-exist-project:
  - automation
  - backup
  - host
x-exist-title: Clean runs
x-exist-tagline: Prune decree's finished run logs after 30 days, so runs/ never fills the disk
x-exist-docs: /docs/flows#housekeeping
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - decree_prune
---
decree's official `decree_prune` plugin deletes this project's finished runs older than 30 days, every
Sunday at 03:00 (`PRUNE_OLDER_THAN` in the project's `.env` changes the age).

Every run's events.jsonl and script logs are shipped to Loki and kept 30 days, so this prunes a
local copy, not the history: Grafana's decree dashboards read Loki. It never touches a run
that has not finished, or a child run whose parent is still going.
