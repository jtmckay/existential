---
machine: nextcloud_rclone_remote
---

Configure the `nextcloud` rclone remote (WebDAV, using the rendered admin
credentials) that `file-processor` downloads through — every path
`file-router` emits, including the `workspace/` mount.

Without this, any file processor with `rclone_src: nextcloud` (the default —
see `services/automation/webhook/config.yml`) fails every download with
`didn't find section in config file ("nextcloud")`, even though the event
routing itself works fine.

Safe to re-run — an existing `[nextcloud]` remote is left alone. Copy to
automation/migrations/ to activate.
