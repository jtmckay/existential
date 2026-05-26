---
cron: "30 2 * * *"
routine: volume-backup
TIER: nightly
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

Tar each Docker volume in `VOLUMES` and rclone it to
`${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/<volume>/`. Files older
than 7 days are pruned at the end of the run.

`VOLUMES` format: one entry per line, whitespace-separated:
  `<volume_name> <comma,separated,consumer,containers>`

The consumer list is used by `./existential.sh setup backup-restore` to
decide which containers must be stopped before a destructive restore
(restores wipe the volume before extracting the tar). Backups are
read-only — the consumer list is informational at backup time.

**Important:** every volume you list here must also be mounted into the
`decree-backup` service in `services/decree/docker-compose.yml.example`
so the container can actually see the volume. Without the mount, the
volume is silently skipped.

Large data stores (loki_data, prometheus_data, minio_data, nextcloud_data)
are intentionally omitted — tarring multi-GB stores is slow. Consider
rclone-syncing those live, or accept rebuild on disaster.

Copy this file into `services/decree/decree-backup/cron/` to activate.
