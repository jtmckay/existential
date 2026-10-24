---
name: Capture
tagline: The webhook and Nextcloud — a POST, or a file from your phone, becomes decree work
e2e: false
e2e_skip: Nextcloud's file events need the desktop client or a real upload to mean anything; e2e covers the chain as its own check
services:
  - var: EXIST_IS_SERVICES_AUTOMATION_WEBHOOK
    label: automation-webhook (authenticated POSTs become decree messages)
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud (files + file events)
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree (runs what they queue)
done:
  files:
    - volumes/workspace_data/.decree/migrations/23-nextcloud-rclone-remote.md
    - volumes/workspace_data/.decree/migrations/27-nextcloud-file-events.md
---

An add-on, not part of Core: capture from outside the work dir.
automation-webhook turns an authenticated POST into a decree message, which is
how a phone shortcut, an ntfy action or another machine queues work. Nextcloud
is the prime example of capture from a phone: it is what your phone and laptop
sync to, and the reason a file landing in it can *trigger* something. It serves
the workspace (`volumes/workspace_data`, the tree code-server already edits) as
the `workspace` folder, so the desktop client keeps a copy on every machine you
use. Files usually live on another server, so this is the whole setup, by hand.

Nothing here is the only way in: everything the webhook triggers can also be
started from code-server's terminal, e.g. `cd /workspace && echo | decree emit
--machine look_back`.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_SERVICES_AUTOMATION_WEBHOOK=true
       EXIST_IS_NAS_NEXTCLOUD=true

       ./existential.sh
       docker compose up -d

The webhook's endpoints (`/capture`, `/you-were-here`, `/look-back`, `/notify`,
`/files`, ...) are `volumes/workspace_data/.decree/decree-go-rest.yml`; the
bearer secret is AUTOMATION_WEBHOOK_SECRET in services/automation-webhook/.env.
Reach it at https://automation-webhook.${EXIST_DOMAIN} through the **Network**
quest's Caddy, or from any container at http://automation-webhook:8801.

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

       ./existential.sh test automation-webhook nextcloud

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
