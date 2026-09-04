---
routine: nextcloud-rclone-remote
---

Configure the `nextcloud` rclone remote (WebDAV, using the rendered admin
credentials) that `file-processor` downloads through — including anything
reached via Nextcloud's `/S3` external-storage mount, such as
`workspace-pull.sh`'s live MinIO -> local pull for `workspace/`.

Without this, any file processor with `rclone_src: nextcloud` (the default —
see `services/automation/webhook/config.yml`) fails every download with
`didn't find section in config file ("nextcloud")`, even though the event
routing itself works fine.

Safe to re-run — an existing `[nextcloud]` remote is left alone. Copy to
automation/migrations/ to activate.
