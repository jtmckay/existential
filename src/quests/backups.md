---
name: Backups
tagline: Nightly database and volume backups, one cron file per service, all in one daemon
e2e: false
e2e_skip: Requires a configured off-box rclone remote to back up to
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree (runs the backups)
done:
  env:
    - EXIST_BACKUP_RCLONE_REMOTE
---

Every backup in this stack runs in one daemon — `automation-backup` — which
mounts `volumes/` wholesale and holds every service's DB credentials. That is
why adding a service to the schedule is **one cron file**, never a new sidecar.

  Databases (postgres / mariadb / mongo):  pg_dump / mysqldump / mongodump → rclone
  Volumes:                                 tar.gz → rclone
  SQLite:                                  .backup → rclone

Nightly copies are kept 7 days, weekly copies 28.

── 1. Say where backups go ───────────────────────────────────────────────

Nothing is backed up anywhere until this is set. It writes
EXIST_BACKUP_RCLONE_REMOTE:

       ./existential.sh run backup-config

── 2. Copy a cron per service you actually enabled ───────────────────────

Templates live in `services/automation/backup/cron.example/`; copying one into
`cron/` is what activates it. Take only the ones you need:

       B=services/automation/backup
       mkdir -p "$B/cron"

       # Core services
       cp $B/cron.example/nextcloud-db-backup-nightly.md       $B/cron/   # DB only
       cp $B/cron.example/workspace-volume-backup-nightly.md   $B/cron/   # the workspace: your files + the agent's
       cp $B/cron.example/hermes-volume-backup-nightly.md      $B/cron/   # agent config + skills
       cp $B/cron.example/openviking-volume-backup-nightly.md  $B/cron/   # the vector index
       cp $B/cron.example/honcho-db-backup-nightly.md          $B/cron/   # agent memory

       # Everything else, if you enabled it
       cp $B/cron.example/actual-budget-volume-backup-nightly.md $B/cron/ # whole DB is one volume
       cp $B/cron.example/appsmith-volume-backup-nightly.md      $B/cron/ # embedded mongo/redis/pg
       cp $B/cron.example/immich-db-backup-nightly.md            $B/cron/
       cp $B/cron.example/immich-volume-backup-nightly.md        $B/cron/
       cp $B/cron.example/lowcoder-db-backup-nightly.md          $B/cron/
       cp $B/cron.example/lowcoder-volume-backup-nightly.md      $B/cron/
       cp $B/cron.example/mealie-db-backup-nightly.md            $B/cron/
       cp $B/cron.example/mealie-volume-backup-nightly.md        $B/cron/
       cp $B/cron.example/nocodb-db-backup-nightly.md            $B/cron/
       cp $B/cron.example/nocodb-volume-backup-nightly.md        $B/cron/
       cp $B/cron.example/uptime-kuma-sqlite-backup-nightly.md   $B/cron/

Want longer retention as well? Every template has a `-weekly.md` twin — copy it
the same way, alongside the nightly one.

── 3. Prove it works before you need it ──────────────────────────────────

Trigger a run now rather than waiting for the schedule:

       cp services/automation/backup/cron/*-backup-nightly.md \
          services/automation/backup/inbox/

Each copy is a message like any other, so it runs once now. Then check the
runs with `docker exec automation-backup decree status` — and, more to the point, check
the files actually landed on the remote.

── 4. Restore ────────────────────────────────────────────────────────────

       ./existential.sh run backup-restore

── Why here and not in `automation` ──────────────────────────────────────

`automation-backup` does no reasoning and calls no model, so it can safely hold
master credentials and mount every volume. `automation` puts what it reads in
front of a model, so what it can reach is what a prompt injection can reach —
which is why backups, `notes-pull` and `triage` all live on this side.
