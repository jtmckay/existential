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
