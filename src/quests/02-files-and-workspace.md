---
name: Files & Workspace
tagline: Nextcloud, file events, and one workspace you, your devices and the agent share
e2e: true
services:
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud (files + file events)
  - var: EXIST_IS_SERVICES_CODE_SERVER
    label: code-server (editor + terminal over the workspace)
done:
  files:
    - automation/migrations/23-nextcloud-rclone-remote.md
    - automation/migrations/27-nextcloud-file-events.md
    - automation/cron/outbox-relay.md
---

The storage slice of Core. Nextcloud is what your phone and laptop sync to, and
the reason a file landing in it can *trigger* something. The workspace
(`volumes/workspace_data`) is the one tree you, code-server, hermes and
OpenViking all see — Nextcloud serves it as the `workspace` folder, so the
desktop client keeps a copy on every machine you use.

Core does everything below in one go. Do it yourself to understand the wiring.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_NAS_NEXTCLOUD=true
       EXIST_IS_SERVICES_CODE_SERVER=true

       ./existential.sh
       docker compose up -d

Nextcloud installs itself, mounts the workspace at `/workspace` in Files, and
starts `nextcloud-cron`, which runs its background jobs — including delivering
file events. There is nothing to click.

── 2. Teach rclone how to reach Nextcloud ────────────────────────────────

Everything that downloads a file out of Nextcloud (every file processor, the
notes routines) goes through one rclone remote. Without it they all fail with
"didn't find section in config file".

       mkdir -p automation/migrations/
       cp automation-examples/migrations/23-nextcloud-rclone-remote.md \
          automation/migrations/

A migration runs **once**, the first time decree sees it, after the service it
configures is healthy. There is nothing to schedule and nothing to re-run.

── 3. Point Nextcloud's file events at decree ────────────────────────────

       cp automation-examples/migrations/27-nextcloud-file-events.md \
          automation/migrations/
       docker compose restart automation

From then on every upload through Nextcloud — desktop client, web UI, WebDAV —
runs `file-router`, which hands the file to any processor whose PATTERN
matches. Writes that do NOT go through Nextcloud — hermes, code-server, decree
itself — fire nothing. That is on purpose: it is what stops an agent's answer
from triggering another run.

── 4. Let the agent reach decree ─────────────────────────────────────────

An agent confined to the workspace drops a message in `workspace/outbox/`
instead of ever touching `automation/` directly. `outbox-relay` picks it up
within a minute:

       mkdir -p automation/cron/
       cp automation-examples/cron/outbox-relay.md automation/cron/
       docker compose restart automation

── 5. Sync it to your machines ───────────────────────────────────────────

Install the Nextcloud desktop client (nextcloud.com/install), log in at
https://nextcloud.${EXIST_DOMAIN} with the admin credentials from
nas/nextcloud/.env, and sync the `workspace` folder. Edit there; the server
side is just where it lives.

── 6. Check it ───────────────────────────────────────────────────────────

       ./existential.sh test nextcloud code-server

Editor and terminal over the same tree: https://code-server.${EXIST_DOMAIN}
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
