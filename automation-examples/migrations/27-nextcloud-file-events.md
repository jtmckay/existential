---
machine: nextcloud_file_events
---

Register Nextcloud's file-event webhooks (written, deleted, renamed) against
decree's `/files` endpoint, so an upload through Nextcloud — the desktop
client, the web UI, WebDAV — runs `file-router` and any matching file
processor.

Without this, Nextcloud works normally and nothing downstream ever hears about
a file.

Requires nas/nextcloud (`EXIST_IS_NAS_NEXTCLOUD`) enabled. Copy to
volumes/workspace_data/.decree/migrations/ to activate.
