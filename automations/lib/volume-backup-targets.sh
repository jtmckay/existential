#!/usr/bin/env bash
# Volume backup targets registry — sourced by:
#   src/backup-runner.sh     (inside existential-backup, does the tar/restore)
#   src/setup/backup-restore.sh  (host-side, does the running-container pre-check)
#
# Each entry is "<volume>|<comma-separated consumer containers>". The consumer
# list lets the pre-check know which docker services must be stopped before a
# destructive restore — Docker happily lets two containers mount the same
# volume, so safety is on us.
#
# DB volumes are NOT listed here — they're covered by db-backup.sh's logical
# pg_dump / mysqldump / mongodump.
#
# To add a new volume: append a line here AND add a matching mount line to the
# `existential-backup` service in existential-compose.yml so the container can
# actually see the volume.

VOLUME_TARGETS=(
  # Service data
  "actual_budget_data|actual-budget"
  "appsmith_data|appsmith"
  "hermes_agent_data|hermes-agent,hermes-workspace"
  "lightrag_rag_storage_data|lightrag"
  "lowcoder_data|lowcoder-api-service"
  "lowcoder_assets|lowcoder-api-service,lowcoder-frontend"
  "mealie_data|mealie"
  "nocodb_data|nocodb"
  "open_webui_data|open-webui"
  "vikunja_data|vikunja"

  # Hosting / infra
  "grafana_data|grafana"
  "portainer_data|portainer"
  "uptime_kuma_data|uptime-kuma"

  # Large stores — uncomment if you actually want them backed up. Tar of a
  # multi-GB store is slow; consider rclone-syncing the live tree instead, or
  # accept rebuild on disaster.
  # "loki_data|loki"
  # "prometheus_data|prometheus"
  # "minio_data|minio"
  # "nextcloud_data|nextcloud"
)

# Helpers — sourced by both the runner and the host-side restore script.

backup_targets_volumes() {
    local entry
    for entry in "${VOLUME_TARGETS[@]}"; do
        printf '%s\n' "${entry%%|*}"
    done
}

backup_targets_consumers() {
    local needle="$1" entry
    for entry in "${VOLUME_TARGETS[@]}"; do
        if [ "${entry%%|*}" = "$needle" ]; then
            printf '%s\n' "${entry#*|}" | tr ',' '\n'
            return 0
        fi
    done
    return 1
}
