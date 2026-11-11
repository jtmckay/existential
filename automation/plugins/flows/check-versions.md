---
machine: plugin
automation: check-versions
name: Version updates
tagline: Mondays, a notification listing every service with a newer image
docs: /docs/flows#housekeeping
services:
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_SERVICES_NTFY
needs:
  - check_versions
cron:
  check-versions: |
    ---
    cron: "0 9 * * MON"
    machine: check_versions
    ---

    Weekly image version check. Sends an ntfy notification listing every service
    with a newer upstream tag. Silent when all tags are current.

    Runs Mondays at 09:00. To apply updates after being notified:
      ./existential.sh run check-versions --update
      docker compose pull && docker compose up -d
---

When one arrives:
  ./existential.sh run check-versions --update
  ./existential.sh && docker compose pull && docker compose up -d
