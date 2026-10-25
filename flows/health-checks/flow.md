---
name: Health checks
tagline: Probe a service every 15 minutes and tell your phone when it stops answering
docs: /docs/flows#housekeeping
services:
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_SERVICES_NTFY
default: true
---

It probes ntfy. To probe another service, copy
volumes/workspace_data/.decree/cron/health-checks.md to health-check-<slug>.md and set
SERVICE_NAME and SERVICE_URL (http://<container>:<port>/<health path>) in its params.
