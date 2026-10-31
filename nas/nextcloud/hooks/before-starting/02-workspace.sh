#!/bin/sh
# nextcloud — mount the workspace and the NAS share into Files, and let file
# events reach decree.
#
# Runs on every start (before-starting), so every step is idempotent.
#
#   /workspace (workspace_data) and /nas (nextcloud_share) → a Local
#   external storage each at the same path, applicable to all users. Local, not
#   a copy: hermes, code-server and decree write /workspace, anything on the NAS
#   writes /nas, and filesystem_check_changes lets Nextcloud notice when they
#   do. nextcloud-cron's files:scan covers the rest of /workspace.
#
#   allow_local_remote_servers — webhook_listeners refuses to POST to a private
#   address without it ("violates local access rules"), and automation-webhook
#   is only ever on the exist bridge. The webhooks themselves are registered by
#   decree's nextcloud-file-events migration: that needs the HTTP API, which
#   is not up yet while this hook runs.
#
# Needs the exec bit: the image's run_path skips hook scripts without it.
# Exits 0 on every path: a failing before-starting hook stops apache from ever
# starting, and a missing mount is not worth losing Nextcloud over.
set -u

occ() { php /var/www/html/occ "$@"; }

if ! occ status 2>/dev/null | grep -q 'installed: true'; then
    echo "[nextcloud] not installed yet — skipping workspace mount."
    exit 0
fi

{
    occ config:system:set allow_local_remote_servers --type=boolean --value=true >/dev/null &&
    occ app:enable files_external webhook_listeners >/dev/null &&
    for dir in /workspace /nas; do
        if ! occ files_external:list --output=json 2>/dev/null | grep -q "\"mount_point\":\"\\\\${dir}\""; then
            id=$(occ files_external:create "$dir" local null::null -c datadir="$dir" | tr -dc '0-9') &&
            occ files_external:option "$id" filesystem_check_changes 1 &&
            echo "[nextcloud] mounted ${dir} (mount ${id})"
        fi
    done
} || echo "[nextcloud] WARNING: workspace mount / file-event setup failed — see above"

exit 0
