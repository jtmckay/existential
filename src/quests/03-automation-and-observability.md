---
name: Automation and Observability
tagline: Decree for headless automation, Grafana + Loki + Prometheus for visibility
e2e: true
services:
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree
  - var: EXIST_IS_HOSTING_GRAFANA
    label: Grafana
  - var: EXIST_IS_HOSTING_LOKI
    label: Loki
  - var: EXIST_IS_HOSTING_PROMETHEUS
    label: Prometheus
---

Decree is the automation engine that runs routines on a schedule, responds
to webhooks, processes your inbox, and connects services together.
Grafana + Loki + Prometheus give you dashboards, logs, and metrics so you
can see exactly what's happening across your homelab.

Docs: https://existential.company/docs/decree

Decree is headless — there is no click-through UI. Control it via:
  - Scheduled cron files in services/decree/decree/cron/
  - HTTP webhooks:  https://decree-webhook.x.internal (API, not a UI)
  - Lowcoder control panel (auto-decree-ui quest)
  - Telegram bot (auto-telegram quest)
  - Manual trigger: docker exec decree decree run <routine-name>

Observe it via:
  - Grafana:     https://grafana.x.internal
  - Prometheus:  https://prometheus.x.internal

Activate the clean-runs cron (prunes old run logs weekly) — this is the
general pattern for every decree cron: copy the .example template into the
live cron/ dir, then restart the daemon that owns it:
  mkdir -p services/decree/decree/cron/
  cp services/decree/decree/cron.example/clean-runs.md services/decree/decree/cron/
  docker compose restart decree
