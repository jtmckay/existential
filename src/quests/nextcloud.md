---
name: Nextcloud
tagline: File sync for your devices, and the file events that let decree react to an upload
e2e: false
services:
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud (files + file events)
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree (receives the file events)
done:
  files:
    - volumes/workspace_data/.decree/migrations/23-nextcloud-rclone-remote.md
    - volumes/workspace_data/.decree/migrations/27-nextcloud-file-events.md
---

Nextcloud is what your phone and laptop sync to, and the reason a file landing
in it can *trigger* something. It serves the workspace (`volumes/workspace_data`,
the tree code-server already edits) as the `workspace` folder, so the desktop
client keeps a copy on every machine you use. Core does not install it — files
usually live on another server — so this is the whole setup, by hand.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_NAS_NEXTCLOUD=true

       ./existential.sh
       docker compose up -d

Nextcloud installs itself, mounts the workspace at `/workspace` in Files, and
starts `nextcloud-cron`, which runs its background jobs — including delivering
file events. There is nothing to click.

── 2. Teach rclone how to reach Nextcloud ────────────────────────────────

Everything that downloads a file out of Nextcloud (every file processor, the
notes machines) goes through one rclone remote. Without it they all fail with
"didn't find section in config file".

       mkdir -p volumes/workspace_data/.decree/migrations/
       cp automation-examples/migrations/23-nextcloud-rclone-remote.md \
          volumes/workspace_data/.decree/migrations/

A migration runs **once**, the first time decree sees it, after the service it
configures is healthy. There is nothing to schedule and nothing to re-run.

── 3. Point Nextcloud's file events at decree ────────────────────────────

       cp automation-examples/migrations/27-nextcloud-file-events.md \
          volumes/workspace_data/.decree/migrations/

From then on every upload through Nextcloud — desktop client, web UI, WebDAV —
runs `file_router`, which hands the file to any processor whose PATTERN
matches. Writes that do NOT go through Nextcloud — hermes, code-server, decree
itself — fire nothing. That is on purpose: it is what stops an agent's answer
from triggering another run.

── 4. Sync it to your machines ───────────────────────────────────────────

Install the Nextcloud desktop client (nextcloud.com/install), log in at
https://nextcloud.${EXIST_DOMAIN} with the admin credentials from
nas/nextcloud/.env, and sync the `workspace` folder. Edit there; the server
side is just where it lives.

── 5. Check it ───────────────────────────────────────────────────────────

       ./existential.sh test nextcloud

Files: https://nextcloud.${EXIST_DOMAIN}

── Where the data actually lives ─────────────────────────────────────────

Every volume is a host bind mount under `volumes/<name>` — never a
Docker-managed volume — so it is visible, host-owned and inspectable. To move
the bulk file volumes onto a NAS, run the **NAS Storage** quest; databases stay
on local disk no matter what, because NFS corrupts an embedded DB's locking.

Backups for Nextcloud's database and the workspace are one cron file each — see
the **Backups** quest.

── What to build on this ─────────────────────────────────────────────────

A file landing in Nextcloud is the trigger behind most of the unnumbered
quests: **File Change Processing** (the mechanism), **Image OCR**,
**Recording Transcription**, and **Workspace Agent**.
