---
machine: plugin
automation: nextcloud-capture
name: Files from your phone start work
tagline: A file uploaded through Nextcloud runs every file processor whose pattern matches it
docs: /docs/decree/file-change-processing
services:
  - EXIST_IS_NAS_NEXTCLOUD
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_SERVICES_AUTOMATION_WEBHOOK
needs:
  - nextcloud_file_events
  - nextcloud_rclone_remote
  - file_router
migrations:
  23-nextcloud-rclone-remote: |
    ---
    machine: nextcloud_rclone_remote
    ---

    Configure the `nextcloud` rclone remote (WebDAV, using the rendered admin
    credentials) that `file-processor` downloads through — every path
    `file_router` emits, including the `workspace/` mount.

    Without this, any file processor with `rclone_src: nextcloud` (the default —
    see `workspace/.decree/decree-go-rest.yml`) fails every download with
    `didn't find section in config file ("nextcloud")`, even though the event
    routing itself works fine.

    Safe to re-run — an existing `[nextcloud]` remote is left alone.
    `./existential.sh flow on nextcloud-capture` activates it.
  27-nextcloud-file-events: |
    ---
    machine: nextcloud_file_events
    ---

    Register Nextcloud's file-event webhooks (written, deleted, renamed) against
    decree's `/files` endpoint, so an upload through Nextcloud — the desktop
    client, the web UI, WebDAV — runs `file-router` and any matching file
    processor.

    Without this, Nextcloud works normally and nothing downstream ever hears about
    a file.

    Requires nas/nextcloud (`EXIST_IS_NAS_NEXTCLOUD`) enabled.
    `./existential.sh flow on nextcloud-capture` activates it.
---

Sync the workspace folder with the Nextcloud desktop client (nextcloud.com/install),
logging in at https://nextcloud.<domain> with the admin login in nas/nextcloud/.env.
Only uploads through Nextcloud fire; a file an agent writes straight to disk never does.
To write your own processor:
  cp workspace/.decree/lib/file-processors.example/example.sh workspace/.decree/lib/file-processors/<name>.sh
