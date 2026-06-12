---
cron: "0 * * * *"
routine: lightrag-sync-notes
LIGHTRAG_NOTES_REMOTE: nextcloud:/Obsidian
---

Sync Obsidian notes from rclone remote to the lightrag inputs volume every hour.

Set LIGHTRAG_NOTES_REMOTE to match your rclone remote and path
(run `./existential.sh run rclone` to configure the remote if needed).

Copy to decree/cron/ to activate, then restart lightrag-decree.
