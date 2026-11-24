---
name: health-checks
x-exist-project: automation
x-exist-title: Health checks
x-exist-tagline: Probe where your notifications go (or any service) every 15 minutes, and tell your phone when it stops answering
x-exist-docs: /docs/flows#housekeeping
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - service_health
cron:
  health-checks.md: |
    ---
    cron: "*/15 * * * *"
    machine: service_health
    params:
      SERVICE_NAME: notifications
    ---

    Health check cron template for all services accessible from the main decree
    daemon on the exist Docker network.

    Each check is a separate cron file. Copy this file and adjust SERVICE_NAME and
    SERVICE_URL for each service you want to monitor.

    The shipped default leaves SERVICE_URL blank: it checks where this host's
    notifications go, its ntfy, or the controller's Loki when ntfy is off here. A
    check on a container this host does not run (a service that is off here) is
    skipped, not failed, so a copy can stay in place on every host. Results appear
    in Grafana's Decree Overview, from Loki.

    The run's machine is "service_health", not SERVICE_NAME — every copy of
    this cron shares one. The per-service
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
      http://open-webui:8080/health           - open-webui
---

It probes where notifications go: this host's ntfy, or the controller's Loki. To probe another service, copy
volumes/workspace_data/.decree/machines/flow_health_checks/cron/health-checks.md into a
schedules plugin of your own as health-check-<slug>.md, set SERVICE_NAME and SERVICE_URL
(http://<container>:<port>/<health path>) in its params, and accept it.
