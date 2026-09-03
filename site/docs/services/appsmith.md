---
sidebar_position: 10
---

# Appsmith

- Source: https://github.com/appsmithorg/appsmith
- License: [Apache 2.0](https://github.com/appsmithorg/appsmith/blob/release/LICENSE)
- Alternatives: Lowcoder, Retool, Tooljet
- UI: `https://appsmith.<domain>`

Low-code platform for building internal dashboards, admin panels, and automation UIs. Better suited for internal tools; [Lowcoder](./lowcoder) is preferred for customer-facing apps.

## What's in the container

One image, six processes under supervisord — not a thin app server:

| Process | What it is |
|---|---|
| `backend` | Java/Spring API (port 8080 internally) |
| `rts` | Node realtime service (collaborative editing) |
| `editor` | Bundled Caddy — serves the SPA and reverse-proxies `/api` to `backend` on port 80 |
| `mongodb` | Embedded MongoDB, a real single-node replica set — not a client to an external Mongo |
| `redis` | Embedded Redis (sessions, pub/sub) |
| `postgres` | Embedded Postgres — backs only the optional "mockdb" sample datasource |

All three datastores are local-only and live under the one `appsmith_data` volume
(`db: true`; never NFS — it corrupts MongoDB's WiredTiger storage and breaks Postgres's
file locks). The container needs root: Appsmith's entrypoint refuses to initialize the
embedded Postgres as a non-root user.

## Resource footprint

This is one of the heaviest single containers in the stack. Measured on a fresh v2.3
install with no apps or users: memory settles around **1-1.05 GiB idle** (mostly the
JVM backend, ~650 MiB RSS), with a boot-time spike past 1.2 GiB before it settles. The
compose memory limit is `2.5G` to leave real headroom above that for actual use.

## Admin access

`APPSMITH_ADMIN_EMAILS` (set from your `EXIST_EMAIL`) grants instance-admin to that
email on signup — Appsmith's `admin.emails` property. Comma-separate more than one.

## Back it up

Copy `appsmith-volume-backup-{nightly,weekly}.md` from
`services/decree/decree-backup/cron.example/` into `cron/` and restart `decree-backup`.
