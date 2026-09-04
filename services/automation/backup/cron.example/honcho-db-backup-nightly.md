---
cron: "0 2 * * *"
routine: db-backup
TIER: nightly
TARGETS: |
  postgres honcho-postgres _LITERAL_honcho HONCHO_POSTGRES_PASSWORD
---

Dump honcho-postgres nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/honcho-postgres/.
Files older than 7 days are pruned at the end of the run.

This is the agent's cross-session memory — losing it means every hermes conversation
starts cold again.

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
