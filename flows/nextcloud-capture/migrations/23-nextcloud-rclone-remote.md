---
machine: nextcloud_rclone_remote
---

Configure the `nextcloud` rclone remote (WebDAV, using the rendered admin
credentials) that `file-processor` downloads through — every path
`file_router` emits, including the `workspace/` mount.

Without this, any file processor with `rclone_src: nextcloud` (the default —
see `automation/decree-go-rest.yml`) fails every download with
`didn't find section in config file ("nextcloud")`, even though the event
routing itself works fine.

Safe to re-run — an existing `[nextcloud]` remote is left alone.
`./existential.sh flow on nextcloud-capture` activates it.
