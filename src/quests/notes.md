---
name: Notes Sync
tagline: Compile and sync your notes from Nextcloud to Dropbox every 10 minutes
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
done:
  files:
    - volumes/workspace_data/.decree/cron/notes.md
---

Activates a recurring cron that pulls notes from Nextcloud, compiles them,
generates an index, and pushes the result to Dropbox — all inside Decree,
every 10 minutes.

Pipeline each run:
  1. Pull from Nextcloud  (automation/lib/notes/pull-nextcloud.sh)
  2. Compile notes        (automation/lib/notes/compile-notes.sh)
  3. Generate index       (automation/lib/notes/generate-index.sh)
  4. Push to Dropbox      (automation/lib/notes/push-dropbox.sh)

Prerequisites:
  - Nextcloud running (the Capture quest)
  - Dropbox rclone remote configured:
      ./existential.sh run rclone
  - Nextcloud rclone credentials in automation/secrets/

Activate the cron:
  mkdir -p volumes/workspace_data/.decree/cron/
  cp automation-examples/cron/notes.md volumes/workspace_data/.decree/cron/

Logs for each run land in volumes/workspace_data/.decree/runs/ and are queryable in Grafana
via the Decree Overview dashboard.
