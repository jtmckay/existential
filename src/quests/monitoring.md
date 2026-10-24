---
name: Monitoring
tagline: Dashy for one page of links, Loki and Prometheus behind Grafana, Uptime Kuma for the rest of the homelab
e2e: true
services:
  - var: EXIST_IS_SERVICES_DASHY
    label: Dashy (the dashboard)
  - var: EXIST_IS_HOSTING_LOKI
    label: Loki (log store)
  - var: EXIST_IS_HOSTING_PROMETHEUS
    label: Prometheus (metrics store)
  - var: EXIST_IS_HOSTING_GRAFANA
    label: Grafana (dashboards)
  - var: EXIST_IS_HOSTING_UPTIME_KUMA
    label: Uptime Kuma (availability monitor)
done:
  files:
    - hosting/grafana/.env
---

An add-on, not part of Core: "can I see what happened?" Dashy is one page
linking to every web service you enable. Decree's run logs land in Loki,
its success/duration gauges in Prometheus, and Grafana ships with both
datasources and the Decree dashboards already wired. Uptime Kuma watches the
other machines in your homelab, which this box's metrics cannot see.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_SERVICES_DASHY=true
       EXIST_IS_HOSTING_LOKI=true
       EXIST_IS_HOSTING_PROMETHEUS=true
       EXIST_IS_HOSTING_GRAFANA=true
       EXIST_IS_HOSTING_UPTIME_KUMA=true

       ./existential.sh
       docker compose up -d

Each is reached at https://<slug>.${EXIST_DOMAIN}, so this needs the
**Network** quest's Caddy.

── 2. Look at it ─────────────────────────────────────────────────────────

  Dashy:       https://dashy.${EXIST_DOMAIN}       → a tile for every service
  Grafana:     https://grafana.${EXIST_DOMAIN}     → Decree Overview dashboard
  Prometheus:  https://prometheus.${EXIST_DOMAIN}
  Uptime Kuma: https://uptime-kuma.${EXIST_DOMAIN}

Filter the Decree Overview dashboard by `machine` to get a panel per machine.
A machine you activate later shows up there with no dashboard edit.

Uptime Kuma is the one thing here you set up by hand: its first page creates
the admin account, and monitors are added in its UI. Point its notifications at
ntfy (server `http://ntfy:80`).

       ./existential.sh test dashy grafana loki prometheus uptime-kuma

── 3. What is already collected ──────────────────────────────────────────

  loki-alloy                 ships every container's stdout/stderr into Loki
  decree_runs_total{...}     finished runs per machine and final state
  exist_service_healthy{...} per-service gauge, written by triage
  hosting/prometheus/alerts.yml
                             ships alert rules, including
                             ServiceHealthCheckFailing

A decree run that fails reaches you through ntfy (Grafana's decree alert).
The alerts.yml rules show at https://prometheus.${EXIST_DOMAIN}/alerts.

── What to build on this ─────────────────────────────────────────────────

Per-service HTTP probes with their own panel: the **Service Health Monitoring**
quest. Containers-by-hand is Portainer, one flag in the service picker.
