---
cron: "*/10 * * * *"
routine: workspace-sync
---

Bidirectionally sync `workspace/` with the `workspace/` subfolder of the
`nextcloud` MinIO bucket every 10 minutes — edit on either side (the host
filesystem, or the bucket, including through Nextcloud's own `/S3`
external-storage mount) and the other side picks it up. Edits also become S3
events and, through minio-router, run any file processor whose PATTERN
matches.

`workspace/ai/` is excluded. That is the loop break: it is where the agent
automations write, and syncing it would make every answer an event and every
event another run. OpenViking indexes it straight off disk regardless, so past
output stays searchable — it simply cannot trigger anything.

Detection is a poll, so a change takes up to ten minutes to be noticed. Tighten
the schedule if that is too slow; each run is one rclone listing when nothing
changed on either side.

The first run has no prior state, so it uploads the whole workspace in one go
(via `--resync`), then — only once that is safely done — queues a message that
subscribes the `nextcloud` bucket to the decree webhook. Nothing to do by hand;
see workspace-sync.sh's own header for why the ordering matters. Subscribing
applies to everything in that bucket, not just workspace/ — it also backs
Nextcloud's own /S3 folder, so every Nextcloud file event starts firing the
webhook too. That is intentional here.

This cron only covers local -> MinIO in real time (nothing fires when you edit
the bind mount by hand, so it has to poll). MinIO -> local is live instead:
copy automation/lib/file-processors.example/workspace-pull.sh to
automation/lib/file-processors/ (needs `minio-router` and `file-processor`
enabled in services/automation/decree/config.yml — on by default — and the
nextcloud rclone remote, set up by the nextcloud-rclone-remote migration). With
it active, a MinIO- or Nextcloud-side edit shows up in workspace/ within about
a second; this cron still runs and reconciles anything it missed.

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
