---
sidebar_position: 8
---

# NocoDB

- Source: https://github.com/nocodb/nocodb
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: Airtable, Supabase, Baserow, Directus
- UI: `https://nocodb.<domain>`

Turns a database into an Airtable-style spreadsheet UI.

## Services

| Container | Purpose |
|---|---|
| `nocodb` | App server (UI + API), port 8080 |
| `nocodb-postgres` | PostgreSQL — table metadata *and* data |

`nocodb` always talks to `nocodb-postgres` over `NC_DB`; there is no bundled-SQLite path in
this setup (verified — `docker exec nocodb env` shows `NC_DB` pointing at `nocodb-postgres` and
`/api/v1/db/meta/nocodb/info` reports `"connectToExternalDB":true`). `nocodb_pg_data` is
`db: true` — local disk only, never NFS.

## Notes

**`NOCODB_ADMIN_EMAIL`/`NOCODB_ADMIN_PASSWORD` are re-applied on every boot**, not a one-time
seed. Verified: changing your password from the NocoDB UI works immediately, but the next
container restart (an update, a host reboot) silently reverts the super-admin account back to
whatever is in `.env` — including the email. Change your login here, not in the UI.

**Memory.** The `nocodb` app container is a large single Node process (it bundles
monaco-editor, several AI SDKs, `googleapis`, and more); measured RSS settles around 860MiB idle
right after first-boot schema migrations, so the compose limit is 2G (~2.3x idle).
`nocodb-postgres` is a normal small Postgres, ~90-105MiB idle, at a 256M limit.

**Health.** `/api/v1/health` is a hardcoded liveness response — it stays `200` even with
`nocodb-postgres` stopped, so it proves the process is up and nothing else. `exist.test.sh`
instead probes `/api/v1/db/meta/nocodb/info`, which reads through to Postgres and fails the
moment the DB is unreachable.

**Backup.** Copy `nocodb-db-backup-{nightly,weekly}.md` (dumps `nocodb-postgres`) and
`nocodb-volume-backup-{nightly,weekly}.md` (tars `nocodb_data` — attachments and other files
NocoDB writes outside Postgres) from `services/automation/backup/cron.example/` into
`cron/` and restart `automation-backup` to activate.
