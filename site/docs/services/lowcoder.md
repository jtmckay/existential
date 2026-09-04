---
sidebar_position: 11
---

# Lowcoder

- Source: https://github.com/lowcoder-org/lowcoder
- License: [AGPL-3.0](https://github.com/lowcoder-org/lowcoder/blob/main/LICENSE)
- Alternatives: Appsmith, Retool, Tooljet
- UI: `https://lowcoder.<domain>`

Low-code platform for building internal and customer-facing apps — continues from the
abandoned Openblocks project. Its pitch over [Appsmith](./appsmith) is native embedding
(no iframe) for apps you hand to people outside the stack, not just internal dashboards.

## Containers

| Container | Role |
|---|---|
| `lowcoder-frontend` | nginx serving the built app — the only one Caddy routes to |
| `lowcoder-api-service` | Java/Spring API backend |
| `lowcoder-node-service` | Node sandbox that executes JS queries/transformers |
| `lowcoder-mongodb` | App data (users, apps, datasource configs) |
| `lowcoder-redis` | Session/query cache — no persistence (`--save ""`) |

`lowcoder-mongodb` and `lowcoder-redis` are dedicated to this service, not the shared
`nas/redis` (which serves only nextcloud) — every bundled-DB service in this stack
(firecrawl, immich, lowcoder) brings its own, and none of them share.

## Access

Browser access is `https://lowcoder.<domain>` via Caddy, which routes to
`lowcoder-frontend:3000`. `lowcoder-api-service:8080` and `lowcoder-node-service:6060`
have no Caddy hostname and no host port by default (both are commented out in
`docker-compose.exist.yml` for direct debugging) — the frontend is the only container
meant to be reached from outside the `exist` network.

## Enable

```bash
EXIST_IS_SERVICES_LOWCODER=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

## Notes

**Credentials, two different lifetimes.** `LOWCODER_MONGO_ROOT_USERNAME`/`_PASSWORD` seed
mongo's root user only on a genuinely empty volume (the official mongo image's own
behavior) — changing them in `.env` after first boot does nothing until the volume is
reset, same caveat as every other bundled database here. `LOWCODER_SUPERUSER_PASSWORD` is
different: api-service re-applies it to the existing superuser account **on every boot**
(verified by changing it against an already-initialised volume and confirming the stored
password hash changed after a restart). `LOWCODER_API_KEY_SECRET` and
`LOWCODER_DB_ENCRYPTION_PASSWORD`/`_SALT` sit in between — nothing stops you rotating
them, but existing API keys stop verifying and existing stored datasource credentials
stop decrypting once you do.

**Backup.** `lowcoder_mongo_data` (`db: true` — WiredTiger, never NFS) is covered by
`lowcoder-db-backup-{nightly,weekly}.md`, and `lowcoder_data` + `lowcoder_assets_data` by
`lowcoder-volume-backup-{nightly,weekly}.md` — both already exist in
`services/automation/backup/cron.example/`. Copy them into `cron/` and restart
`automation-backup` to activate; nothing else is needed.

**Memory.** `lowcoder-api-service` and `lowcoder-node-service` are both JVM/V8 processes
that size their default heap off the container's memory limit, not off actual load — the
limits in `docker-compose.exist.yml` are set from measured idle usage on a fresh install
(see the comments there), not upstream's defaults, which leave both unbounded.
