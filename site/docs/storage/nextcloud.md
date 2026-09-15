---
sidebar_position: 3
---

# Nextcloud

- Source: https://github.com/nextcloud/server
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: ownCloud, Seafile, Syncthing

File sharing and sync — Dropbox/Google Drive alternative.

Nextcloud ships with its own Redis (`nextcloud-redis`), in the same compose file — there is
nothing to enable separately. See [Cache](#cache) below.

## Setup

Most of Nextcloud's environment variables are read by the installer on the **first** run only,
and ignored afterwards — so set what you care about before you bring it up the first time.

The exception is `trusted_domains`, because that one has to be able to change. `EXIST_DOMAIN` is
the one knob you move to relocate the whole stack, and the installer would otherwise freeze
Nextcloud's allowed hostname at whatever it saw first — leaving it answering *"Access through
untrusted domain"* while every other service followed the new name. A `before-starting` hook
re-applies `trusted_domains` from the environment on every start, so changing `EXIST_DOMAIN` and
re-running is enough.

`overwritehost`, `overwriteprotocol`, `overwrite.cli.url` and `trusted_proxies` do **not** need
that treatment, even though the installer also writes them once: Nextcloud's own
`config/reverse-proxy.config.php` reads them straight from the environment on every request and
overrides whatever is baked into `config.php`, so they already track `EXIST_DOMAIN` without a
restart doing anything special.

## Cache

`nextcloud-redis` (`redis:8.10.1-alpine3.23`, tri-licensed
[RSALv2 / SSPLv1 / AGPLv3](https://redis.io/legal/licenses/) — for commercial hosting, select
AGPLv3 or RSALv2) is Nextcloud's `memcache.distributed` and `memcache.locking` backend
(transactional file locking, so two clients can't corrupt the same file at once) and its PHP
session store. Both are wired by the official `nextcloud` image whenever `REDIS_HOST` is set
(`redis.config.php`, `entrypoint.sh`'s `configure_redis_session`), so this is a hard dependency,
not an optional add-on — which is why it lives in Nextcloud's own compose file rather than being
a service you toggle. Nothing else in the stack talks to it: `firecrawl-redis`,
`lowcoder-redis` and `immich-redis` are separate, per-service instances.

It holds **no volume** and runs with `--save ""`. Locks and sessions are transient by
definition; losing them costs a re-login and clears any stale file lock. Nothing to back up.
No `maxmemory` or eviction policy is set, so redis grows until it hits the container's 128M
limit rather than evicting old keys, at which point Docker's OOM killer restarts it.

`--requirepass` is always on, from `NEXTCLOUD_REDIS_PASSWORD` in `nas/nextcloud/.env` — one key
read by both containers, so the two sides cannot drift. A bare `redis-cli ping` therefore
returns `NOAUTH`, not `PONG`; pass `-a` (see the healthcheck in
`nas/nextcloud/docker-compose.exist.yml`, and `nas/nextcloud/exist.test.sh` for a
dependency-free AUTH+PING over the raw protocol).

## Housekeeping

Any `occ` command can be run from the host:

```bash
docker exec -u www-data nextcloud php /var/www/html/occ <command>
```

### Migrate mimetypes (after major updates)

```bash
docker exec -u www-data nextcloud php /var/www/html/occ maintenance:repair --include-expensive
```

### Add missing indices (after major updates)

```bash
docker exec -u www-data nextcloud php /var/www/html/occ db:add-missing-indices
```

### Cron job

Nextcloud wants `cron.php` run every 5 minutes:

```bash
sudo crontab -e
# Add:
*/5 * * * * docker exec -u www-data nextcloud php /var/www/html/cron.php
```

Verify in Nextcloud: **Administration → Basic settings** — it should switch from `AJAX` to `Cron (Recommended)`.

### Set maintenance window (UTC)

```bash
docker exec -u www-data nextcloud php /var/www/html/occ config:system:set maintenance_window_start --type=integer --value=8
```

## External Storage (SeaweedFS/S3)

Automatic on a fresh install: `hooks/post-installation/01-s3-external-storage.sh` mounts the
`nextcloud` seaweedfs bucket as an "S3" folder the moment `occ maintenance:install` finishes, using
the scoped identity declared in seaweedfs's `s3.json` (never the admin login). If SeaweedFS
was enabled *after* Nextcloud already existed — that hook only runs once, at first install — add
it by hand:

1. Enable **External storage** app: `/settings/apps/featured`
2. Go to **Administration settings → External storage**
3. Add AmazonS3 type with Access key:
   - Bucket: `nextcloud`
   - Hostname: `seaweedfs`
   - Port: `8333`
   - Uncheck "Enable SSL"
   - Check "Enable Path Style"
   - Paste the SeaweedFS access key and secret key (`nas/seaweedfs/.env`, `SEAWEEDFS_NEXTCLOUD_ACCESS_KEY`/`_SECRET_KEY`)

With SeaweedFS enabled, this `/S3` folder also holds a `workspace/` subfolder kept in live sync
with the repo-root `workspace/` directory — see [SeaweedFS](./seaweedfs#workspace-lives-in-the-same-bucket)
and [Getting Started → Workspace](../getting-started#workspace).

## Collabora (office document editing)

Nextcloud does not talk to `nas/collabora` out of the box — the `richdocuments` app has to be
installed and pointed at it. `automation-examples/migrations/22-nextcloud-richdocuments.md`
does this the same way the seaweedfs bucket gets created: copy it to
`automation/migrations/` and restart `automation` to activate. It also sets
`richdocuments`'s `wopi_allowlist` to the `exist` bridge subnet — left blank (upstream's default),
Nextcloud's own admin settings warn that *any* IP that can reach it may make WOPI requests, not
just the actual Collabora container.

To do it by hand instead:

```bash
docker exec -u www-data nextcloud php /var/www/html/occ app:install richdocuments
docker exec -u www-data nextcloud php /var/www/html/occ config:app:set richdocuments wopi_url \
    --value="https://collabora.<domain>"
docker exec -u www-data nextcloud php /var/www/html/occ config:app:set richdocuments wopi_allowlist \
    --value="172.16.0.0/12"
```

Collabora's own admin console lives at `https://collabora.<domain>`, gated by
`COLLABORA_USERNAME`/`COLLABORA_PASSWORD` (`nas/collabora/.env`).

## Calendar

Nextcloud ships CalDAV enabled regardless (the `dav` app), but the Calendar app itself —
the UI at `/apps/calendar`, and the "Personal"/"Contact birthdays" calendars it auto-creates
per user — has to be turned on. `automation-examples/migrations/24-nextcloud-calendar.md` does
that the same way `richdocuments` above gets installed: copy it to `automation/migrations/` and
restart `automation` to activate.

To do it by hand instead:

```bash
docker exec -u www-data nextcloud php /var/www/html/occ app:install calendar
```

### Indexed by OpenViking, answerable by hermes

A calendar app on its own is just a UI — nothing about it is searchable by the stack. Copy
`automation-examples/cron/calendar-extract.md` to `automation/cron/` (restart `automation`) and
every event, recent-past through `CALENDAR_EXTRACT_FUTURE_DAYS` ahead, gets mirrored into
`workspace/ai/calendar/<calendar>/` as one markdown note per event. That's the same tree
`openviking-index-knowledgebase` already indexes, so a hermes department with OpenViking access
can answer "what's on my calendar" or "when's Leon's birthday" the way it answers anything else
in `workspace/` — no new tool, no new integration, just more notes in the same knowledgebase.

The mirror is full-refresh, not append-only: a cancelled or deleted event's note disappears on
the next run, and the directory only ever reflects what's really scheduled. See
`automation/shared_routines/calendar-extract.sh` for the CalDAV details (verified live against
nextcloud:34.0.3, including its `expand` support for recurring events).

## Maintenance

```bash
# Enter maintenance mode
docker exec -u www-data nextcloud php /var/www/html/occ maintenance:mode --on

# Exit maintenance mode
docker exec -u www-data nextcloud php /var/www/html/occ maintenance:mode --off
```

### Restart order

Only matters if `nextcloud_data`'s volume is `nfs: true` **and** `EXIST_NFS_HOST_MOUNT` points at
external storage (e.g. TrueNAS) — otherwise every bind mount is local and ordinary
`docker compose up -d` handles it:

1. The NAS export
2. SeaweedFS
3. Nextcloud
4. Everything else

## Debugging

```bash
# Check pending background jobs
docker exec -it nextcloud-db mariadb -u root -p nextcloud \
    -e "SELECT COUNT(*) FROM oc_jobs WHERE last_run = 0;"

# Manually run cron
time docker exec -u www-data nextcloud php /var/www/html/cron.php
```
