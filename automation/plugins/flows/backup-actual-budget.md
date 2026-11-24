---
name: backup-actual-budget
x-exist-project: backup
x-exist-title: Back up Actual Budget
x-exist-tagline: Actual Budget, backed up nightly and weekly to your rclone remote
x-exist-docs: /docs/decree/automation-backup
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
  - EXIST_IS_SERVICES_ACTUAL_BUDGET
needs:
  - volume_backup
cron:
  actual-budget-volume-backup-nightly.md: |
    ---
    cron: "30 2 * * *"
    machine: volume_backup
    params:
      TIER: nightly
      VOLUMES: |
        actual_budget_data actual-budget
    ---

    Tar actual_budget_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/actual_budget_data/.
    Files older than 7 days are pruned at the end of the run.
  actual-budget-volume-backup-weekly.md: |
    ---
    cron: "30 3 * * SUN"
    machine: volume_backup
    params:
      TIER: weekly
      VOLUMES: |
        actual_budget_data actual-budget
    ---

    Weekly tar of actual_budget_data volume (retained 28 days).
---

Backups go to the rclone remote in EXIST_BACKUP_RCLONE_REMOTE (.env.shared); add it once with
./existential.sh run rclone. Restore with ./existential.sh run backup-restore. For another
schedule, edit the cron files in services/automation-backup/machines/flow_backup_actual_budget/cron/.
