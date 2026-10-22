---
name: Observability
tagline: Loki for logs, Prometheus for metrics, Grafana as the window onto both
e2e: true
services:
  - var: EXIST_IS_HOSTING_LOKI
    label: Loki (log store)
  - var: EXIST_IS_HOSTING_PROMETHEUS
    label: Prometheus (metrics store)
  - var: EXIST_IS_HOSTING_GRAFANA
    label: Grafana (dashboards)
done:
  files:
    - hosting/grafana/.env
---

The "can I see what happened?" slice of Core. Decree's run logs land in Loki,
its success/duration gauges in Prometheus, and Grafana ships with both
datasources and the Decree dashboards already wired.

This is the one slice with nothing to activate — it comes up configured.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_HOSTING_LOKI=true
       EXIST_IS_HOSTING_PROMETHEUS=true
       EXIST_IS_HOSTING_GRAFANA=true

       ./existential.sh
       docker compose up -d

── 2. Look at it ─────────────────────────────────────────────────────────

  Grafana:     https://grafana.${EXIST_DOMAIN}     → Decree Overview dashboard
  Prometheus:  https://prometheus.${EXIST_DOMAIN}

Filter the Decree Overview dashboard by `machine` to get a panel per machine.
A machine you activate later shows up there with no dashboard edit.

       ./existential.sh test grafana loki prometheus

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
quest. Containers-by-hand and an external uptime view are separate services you
can enable from the service picker (Portainer, Uptime Kuma) — neither needs a
quest, both come up configured.
