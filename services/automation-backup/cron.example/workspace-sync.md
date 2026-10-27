---
cron: "*/5 * * * *"
machine: workspace_sync
---

Two-way syncs `workspace/` with a folder in Nextcloud, so it is the same tree you
edit from your desktop, phone and Obsidian. Nextcloud can run on another server
or in this stack.

Set `EXIST_NEXTCLOUD_DOMAIN`, `EXIST_NEXTCLOUD_USER` and
`EXIST_NEXTCLOUD_APP_PASSWORD` in `.env` (an app password, from Nextcloud's
Settings > Security), then `docker compose up -d automation-backup`. Until all
three are set, each run does nothing. The folder is
`EXIST_NEXTCLOUD_WORKSPACE_DIR` (default `workspace`); the first run merges both
sides and deletes nothing.

Never synced: anything a `.gitignore` under `workspace/` ignores, and every
`.git/`. That keeps decree's run state local; add a line to keep anything else
local.

A run that would delete over half the files on one side deletes nothing and
asks you instead (ntfy, and `decree status` in automation-backup). Until you
answer `delete` or `keep`, later runs skip.
