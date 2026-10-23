---
name: Service Health Monitoring
tagline: HTTP health probes for your services, visible in Grafana and alerting via ntfy
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
  - var: EXIST_IS_HOSTING_PROMETHEUS
    label: Prometheus
  - var: EXIST_IS_HOSTING_GRAFANA
    label: Grafana
done:
  files:
    - volumes/workspace_data/.decree/cron/health-checks.md
---

Adds per-service health check crons to the main Decree daemon. Each cron
probes a service URL every 15 minutes. Results flow automatically to:

  - Prometheus: decree_runs_total{machine="service_health"} counter
  - Loki:       each run's events and log
  - Grafana:    the Decree Overview dashboard, and an ntfy alert on a failed run
  - Alerting:   ServiceHealthCheckFailing (hosting/prometheus/alerts.yml)
                rides triage's per-service exist_service_healthy gauge

Core (and the Automation quest) already copies the base `health-checks.md`
cron in. This quest is the next step: one copy per service you want probed
by name.

Setup — for each service you want to monitor:

  1. Copy the cron template under a name of its own:
       mkdir -p volumes/workspace_data/.decree/cron/
       cp automation-examples/cron/health-checks.md \
          volumes/workspace_data/.decree/cron/health-check-<slug>.md

  2. Edit the copy and set, under params:
       SERVICE_NAME: <slug>          # display name in the run log
       SERVICE_URL:  http://<container>:<port>/<health-path>

Example health endpoints per service:
  http://ollama:11434/api/tags              ollama
  http://mealie:9000/api/app/about          mealie
  http://nocodb:8080/api/v1/health          nocodb
  http://grafana:3000/api/health            grafana
  http://prometheus:9090/-/healthy          prometheus
  http://loki:3100/ready                   loki
  http://ntfy:80/v1/health                ntfy
  http://hermes-agent:8642/health           hermes
  http://open-webui:8080/health            open-webui

In Grafana, filter the Decree Overview dashboard by routine=service-health
to see a panel per monitored service.
