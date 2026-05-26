---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  actual_budget_data         actual-budget
  appsmith_data              appsmith
  hermes_agent_data          hermes-agent,hermes-workspace
  lightrag_rag_storage_data  lightrag
  lowcoder_data              lowcoder-api-service
  lowcoder_assets            lowcoder-api-service,lowcoder-frontend
  mealie_data                mealie
  nocodb_data                nocodb
  open_webui_data            open-webui
  vikunja_data               vikunja
  grafana_data               grafana
  portainer_data             portainer
  uptime_kuma_data           uptime-kuma
---

Weekly counterpart to volume-backup-nightly. Same `VOLUMES` list,
written to `${EXIST_BACKUP_RCLONE_REMOTE}/weekly/volumes/<volume>/` with
a 28-day retention window.

If you change the nightly `VOLUMES`, change the weekly one to match.

Copy this file into `services/decree/decree-backup/cron/` to activate.
