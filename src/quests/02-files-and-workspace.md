---
name: Files & Workspace
tagline: Nextcloud, an S3 bucket that fires events, and one workspace/ tree you and the agent share
e2e: true
services:
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud (files)
  - var: EXIST_IS_NAS_SEAWEEDFS
    label: SeaweedFS (S3 + file events)
  - var: EXIST_IS_SERVICES_CODE_SERVER
    label: code-server (editor + terminal over workspace/)
done:
  files:
    - automation/migrations/23-nextcloud-rclone-remote.md
    - services/automation/backup/cron/workspace-sync.md
    - automation/lib/file-processors/workspace-pull.sh
    - automation/lib/file-processors/outbox-relay.sh
---

The storage slice of Core. Nextcloud is what your phone and laptop sync to;
SeaweedFS is the bucket underneath it, and the reason a file landing anywhere
can *trigger* something. `workspace/` at the repo root is the one tree you,
code-server, hermes and OpenViking all see — kept in step with the bucket both
ways.

Core does everything below in one go. Do it yourself to understand the wiring.

── 1. Enable and start ───────────────────────────────────────────────────

       EXIST_IS_NAS_NEXTCLOUD=true
       EXIST_IS_NAS_SEAWEEDFS=true
       EXIST_IS_SERVICES_CODE_SERVER=true

       ./existential.sh
       docker compose up -d

`./existential.sh` creates `workspace/` and seaweedfs pre-creates the
`nextcloud` bucket itself — there is no migration for either.

── 2. Teach rclone how to reach Nextcloud ────────────────────────────────

Everything that downloads a file out of Nextcloud (every file processor, the
notes routines, workspace-pull below) goes through one rclone remote. Without
it they all fail with "didn't find section in config file".

       mkdir -p automation/migrations/
       cp automation-examples/migrations/23-nextcloud-rclone-remote.md \
          automation/migrations/
       docker compose restart automation

A migration runs **once**, the first time decree sees it, after the service it
configures is healthy. There is nothing to schedule and nothing to re-run.

── 3. Keep workspace/ and the bucket in step ─────────────────────────────

`workspace-sync` bisyncs `workspace/` with the `workspace/` subfolder of the
nextcloud bucket every 10 minutes. It lives in the **backup** daemon, because it
needs bulk volume access and does no reasoning:

       mkdir -p services/automation/backup/cron/
       cp services/automation/backup/cron.example/workspace-sync.md \
          services/automation/backup/cron/
       docker compose restart automation-backup

`workspace/ai/` is deliberately excluded — that is where the agent automations
write, and syncing it back would make every answer a new event, forever.

── 4. Make bucket edits show up in seconds ───────────────────────────────

The cron above is the slow half. `workspace-pull.sh` is the live half: a
bucket-side edit reaches `workspace/` in about a second over the webhook.
`outbox-relay.sh` is the only door the other way — an agent confined to
`workspace/` drops a message in `workspace/outbox/` instead of ever touching
`automation/` directly.

       mkdir -p automation/lib/file-processors/
       cp automation/lib/file-processors.example/workspace-pull.sh \
          automation/lib/file-processors.example/outbox-relay.sh \
          automation/lib/file-processors/

Processor scripts are bind-mounted live — no restart. `s3-router` and
`file-processor` are already enabled by default in
`services/automation/decree/config.exist.yml`, so there is nothing to whitelist.

── 5. Check it ───────────────────────────────────────────────────────────

       ./existential.sh test nextcloud seaweedfs code-server

Editor and terminal over the same tree: https://code-server.${EXIST_DOMAIN}
Files: https://nextcloud.${EXIST_DOMAIN}

── Where the data actually lives ─────────────────────────────────────────

Every volume is a host bind mount under `volumes/<name>` — never a
Docker-managed volume — so it is visible, host-owned and inspectable. To move
the bulk file volumes onto a NAS, run the **NAS Storage** quest; databases stay
on local disk no matter what, because NFS corrupts an embedded DB's locking.

Backups for Nextcloud's database are one cron file — see the **Backups** quest.

── What to build on this ─────────────────────────────────────────────────

A file landing in the bucket is the trigger behind most of the unnumbered
quests: **File Change Processing** (the mechanism), **Image OCR**,
**Recording Transcription**, and **Workspace Agent**.
