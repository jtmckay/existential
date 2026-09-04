---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  immich_library immich-server
---

Weekly tar of the immich_library volume (retained 28 days). Same DEFAULT-path
caveat as the nightly cron — see that file.

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
