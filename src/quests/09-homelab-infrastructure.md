---
name: Homelab Infrastructure
tagline: Monitoring, containers, and dashboards
e2e: true
services:
  - var: EXIST_IS_HOSTING_PORTAINER
    label: Portainer
  - var: EXIST_IS_HOSTING_GRAFANA
    label: Grafana
  - var: EXIST_IS_HOSTING_PROMETHEUS
    label: Prometheus
  - var: EXIST_IS_HOSTING_LOKI
    label: Loki
  - var: EXIST_IS_HOSTING_UPTIME_KUMA
    label: Uptime Kuma
  - var: EXIST_IS_SERVICES_DASHY
    label: Dashy
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree
---

Portainer manages containers by hand; Grafana + Loki + Prometheus give you
dashboards, logs and metrics; Uptime Kuma watches uptime from the outside;
Dashy is one page linking to all of the above.

If you enabled Decree, activate the one cron worth having on by default —
it prunes old run logs weekly so automations/runs/ doesn't grow forever:

  mkdir -p services/decree/decree/cron/
  cp services/decree/decree/cron.example/clean-runs.md services/decree/decree/cron/
  docker compose restart decree

Everything else here (Portainer, Grafana, Prometheus, Loki, Uptime Kuma,
Dashy) needs no activation step — each comes up configured after
`docker compose up -d`. Grafana ships with the Loki/Prometheus datasources
and Decree dashboards already wired; Dashy's tiles link to every core
service automatically.
