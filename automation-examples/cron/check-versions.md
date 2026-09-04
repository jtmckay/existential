---
cron: "0 9 * * 1"
routine: check-versions
---

Weekly image version check. Sends an ntfy notification listing every service
with a newer upstream tag. Silent when all tags are current.

Runs Mondays at 09:00. To apply updates after being notified:
  ./existential.sh run check-versions --update
  docker compose pull && docker compose up -d
