---
cron: "0 */6 * * *"
routine: openviking-sync
SYNC_REMOTE: "nextcloud:/Obsidian"
SYNC_DEST: /notes
---

Sync notes from the rclone remote into /notes every 6 hours, then trigger
OpenViking to re-index any changed files.

Set SYNC_REMOTE to your rclone remote + path (e.g. "gdrive:/Notes",
"s3:mybucket/notes"). The rclone config lives at /secrets/rclone/rclone.conf.

To sync a different source on a different schedule, copy this file with a new
name and adjust SYNC_REMOTE, SYNC_DEST, and cron independently.

Requires the 01-watch-dirs migration to have run first.

Copy to decree/cron/ to activate.
