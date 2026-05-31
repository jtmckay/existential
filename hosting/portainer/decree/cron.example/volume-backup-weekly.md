---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  portainer_data portainer
---

Weekly tar of portainer_data volume (retained 28 days).

Copy to decree/cron/ to activate.
