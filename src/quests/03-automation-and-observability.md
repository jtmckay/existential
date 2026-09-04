---
name: Automation and Observability
tagline: Decree for headless automation, Grafana + Loki + Prometheus for visibility
e2e: true
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
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
  - Scheduled cron files in automation/cron/
  - HTTP webhooks:  https://automation-webhook.<domain> (API, not a UI)
  - Lowcoder control panel (auto-decree-ui quest)
  - Telegram bot (auto-telegram quest)
  - Manual trigger: drop a message in the inbox it drains —
      printf -- '---\nroutine: <routine-name>\n---\n' > automation/inbox/manual.md

Observe it via:
  - Grafana:     https://grafana.<domain>
  - Prometheus:  https://prometheus.<domain>

Activate the clean-runs cron (prunes old run logs weekly) — this is the
general pattern for every decree cron: copy the .example template into the
live cron/ dir, then restart the daemon that owns it:
  mkdir -p automation/cron/
  cp automation-examples/cron/clean-runs.md automation/cron/
  docker compose restart automation
