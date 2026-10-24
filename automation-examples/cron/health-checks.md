---
cron: "*/15 * * * *"
machine: service_health
params:
  SERVICE_NAME: ntfy
  SERVICE_URL: http://ntfy:80/v1/health
---

Health check cron template for all services accessible from the main decree
daemon on the exist Docker network.

Each check is a separate cron file. Copy this file and adjust SERVICE_NAME and
SERVICE_URL for each service you want to monitor.

The shipped default checks ntfy, which is in Core alongside the daemon that
runs this cron, so it is present on every Core install. Point it at a service that
is NOT enabled and the check fails every run, and alerts every 6 hours, which is
exactly what a default of `grafana` used to do on every Core install (Core does
not include grafana). Results appear in Grafana via
Prometheus (decree_runs_total) and Loki (run logs).

The metric's machine label is "service_health", not SERVICE_NAME — every
copy of this cron shares one series. The per-service
alert in hosting/prometheus/alerts.yml rides triage's exist_service_healthy
gauge instead, which needs no cron file at all.

Example service URLs (container:port/health-path):
  http://ollama:11434/api/tags            - ollama
  http://mealie:9000/api/app/about        - mealie
  http://nocodb:8080/api/v1/health        - nocodb (unauthenticated)
  http://grafana:3000/api/health          - grafana
  http://prometheus:9090/-/healthy        - prometheus
  http://loki:3100/ready                  - loki
  http://automation-webhook:8801/healthz  - automation-webhook
  http://uptime-kuma:3001               - uptime-kuma (any 200)
  http://hermes-agent:8642/health         - hermes
  http://open-webui:8080/health           - open-webui
