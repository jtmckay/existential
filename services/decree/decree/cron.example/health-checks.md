---
cron: "*/15 * * * *"
routine: service-health
SERVICE_NAME: grafana
SERVICE_URL: http://grafana:3000/api/health
---

Health check cron template for all services accessible from the main decree
daemon on the exist Docker network.

Each check is a separate cron file. Copy this file and adjust SERVICE_NAME and
SERVICE_URL for each service you want to monitor. Results appear in Grafana via
Prometheus (decree_run_success metric) and Loki (routine logs).

Prometheus alert: decree_run_success{instance="health-<SERVICE_NAME>"} == 0
fires when a check has been failing. See hosting/prometheus/alerts.yml.

Example service URLs (container:port/health-path):
  http://ollama:11434/api/tags            - ollama
  http://mealie:9000/api/app/about        - mealie
  http://nocodb:8080/api/v1/health        - nocodb (unauthenticated)
  http://grafana:3000/api/health          - grafana
  http://prometheus:9090/-/healthy        - prometheus
  http://loki:3100/ready                  - loki
  http://ntfy:80/v1/health               - ntfy
  http://uptime-kuma:3001               - uptime-kuma (any 200)
  http://hermes-agent:8642/health         - hermes
  http://lightrag:9621/health             - lightrag
  http://open-webui:8080/health           - open-webui
