---
name: workspace-sync
x-exist-project: backup
x-exist-title: Workspace sync
x-exist-tagline: workspace/ kept the same as one other copy, on your NAS or in Nextcloud, every minute
x-exist-docs: /docs/decree/automation-backup
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
needs:
  - workspace_sync
cron:
  workspace-sync.md: |
    ---
    cron: "* * * * *"
    machine: workspace_sync
    ---

    Two-way syncs `workspace/` with one other copy, every minute, so it is the same tree
    wherever you edit it. A file changed on both sides since the last run keeps the newer edit.

    - **On the NAS**: give `EXIST_NFS_SHARE_WORKSPACE` a folder on the NAS (asked
      when `./existential.sh` first sees `automation-backup` on with a NAS). It wins over Nextcloud.
    - **In Nextcloud**: set `EXIST_NEXTCLOUD_DOMAIN`, `EXIST_NEXTCLOUD_USER` and
      `EXIST_NEXTCLOUD_APP_PASSWORD` in `.env` (an app password, from Nextcloud's Settings >
      Security). The folder is `EXIST_NEXTCLOUD_WORKSPACE_DIR` (default `workspace`).

    Then `docker compose up -d automation-backup`. With neither, each run does nothing. The first
    run with a new other end merges both sides and deletes nothing.

    Never synced: anything a `.gitignore` under `workspace/` ignores, and every `.git/`. That
    keeps decree's run state local; add a line to keep anything else local.

    A run that would delete over half the files on one side deletes nothing and asks you instead
    (ntfy, and `decree status` in automation-backup). Until you answer `delete` or `keep`, later
    runs skip.
---

It does nothing until it has a NAS folder (EXIST_NFS_SHARE_WORKSPACE) or Nextcloud keys in .env.
