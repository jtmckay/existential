---
service: nas/nextcloud
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
docker exec nextcloud php /var/www/html/occ <command>
```

### Migrate mimetypes (after major updates)

```bash
docker exec nextcloud php /var/www/html/occ maintenance:repair --include-expensive
```

### Add missing indices (after major updates)

```bash
docker exec nextcloud php /var/www/html/occ db:add-missing-indices
```

### Background jobs

Handled: the `nextcloud-cron` container runs `cron.php` every minute and delivers webhooks as
they are queued, and its first run switches **Administration → Basic settings** from `AJAX` to
`Cron`. Nothing to add to the host's crontab.

### Set maintenance window (UTC)

```bash
docker exec nextcloud php /var/www/html/occ config:system:set maintenance_window_start --type=integer --value=8
```

## The workspace folder

`hooks/before-starting/02-workspace.sh` mounts the `workspace_data` volume as a **Local**
external storage at `/workspace`, applicable to every user. Sync that folder with the desktop client and you are editing the
same tree hermes and code-server see. See [Getting Started → Workspace](../getting-started#workspace).

Nextcloud runs as `EXIST_PUID`, not `www-data`, for exactly this reason: every writer of that
volume has to be the same uid.

Nextcloud is optional sync for the workspace, not what triggers automations there: the stack
sees a workspace change itself, whoever made it ([File Handlers](../decree/file-handlers)).
Every upload through Nextcloud — anywhere, not just the workspace — can also fire a file event
to Decree. See [File Processor](../decree/file-change-processing).

## Collabora (office document editing)

Nextcloud does not talk to `nas/collabora` out of the box — the `richdocuments` app has to be
installed and pointed at it. `automation-examples/migrations/22-nextcloud-richdocuments.md`
does this the same way every other post-startup setup is done: copy it to
`volumes/workspace_data/.decree/migrations/` and restart `automation` to activate. It also sets
`richdocuments`'s `wopi_allowlist` to the `exist` bridge subnet — left blank (upstream's default),
Nextcloud's own admin settings warn that *any* IP that can reach it may make WOPI requests, not
just the actual Collabora container.

To do it by hand instead:

```bash
docker exec nextcloud php /var/www/html/occ app:install richdocuments
docker exec nextcloud php /var/www/html/occ config:app:set richdocuments wopi_url \
    --value="https://collabora.<domain>"
docker exec nextcloud php /var/www/html/occ config:app:set richdocuments wopi_allowlist \
    --value="172.16.0.0/12"
```

Collabora's own admin console lives at `https://collabora.<domain>`, gated by
`COLLABORA_USERNAME`/`COLLABORA_PASSWORD` (`nas/collabora/.env`).

## Calendar

Nextcloud ships CalDAV enabled regardless (the `dav` app), but the Calendar app itself —
the UI at `/apps/calendar`, and the "Personal"/"Contact birthdays" calendars it auto-creates
per user — has to be turned on. `automation-examples/migrations/24-nextcloud-calendar.md` does
that the same way `richdocuments` above gets installed: copy it to `volumes/workspace_data/.decree/migrations/` and
restart `automation` to activate.

To do it by hand instead:

```bash
docker exec nextcloud php /var/www/html/occ app:install calendar
```

### Indexed by OpenViking, answerable by hermes

A calendar app on its own is just a UI — nothing about it is searchable by the stack. Copy
`automation-examples/cron/calendar-extract.md` to `volumes/workspace_data/.decree/cron/` (restart `automation`) and
every event, recent-past through `CALENDAR_EXTRACT_FUTURE_DAYS` ahead, gets mirrored into
`workspace/ai/calendar/<calendar>/` as one markdown note per event. That's the same tree
`openviking-index-knowledgebase` already indexes, so a hermes department with OpenViking access
can answer "what's on my calendar" or "when's Leon's birthday" the way it answers anything else
in `workspace/` — no new tool, no new integration, just more notes in the same knowledgebase.

The mirror is full-refresh, not append-only: a cancelled or deleted event's note disappears on
the next run, and the directory only ever reflects what's really scheduled. See
`automation/scripts/calendar_extract.sh` for the CalDAV details (verified live against
nextcloud:34.0.3, including its `expand` support for recurring events).

## Maintenance

```bash
# Enter maintenance mode
docker exec nextcloud php /var/www/html/occ maintenance:mode --on

# Exit maintenance mode
docker exec nextcloud php /var/www/html/occ maintenance:mode --off
```

Nextcloud's own update check is off, and so is the `survey_client` app: the check sends the
install time, PHP version and a user-count bucket, not just a version request. Updating is
bumping the image tag in `docker-compose.exist.yml`. `hooks/before-starting/03-no-phone-home.sh`
re-applies both on every start.

### Restart order

Only matters if `nextcloud_data`'s volume is `nfs: true` **and** `EXIST_NFS_HOST_MOUNT` points at
external storage (e.g. TrueNAS) — otherwise every bind mount is local and ordinary
`docker compose up -d` handles it:

1. The NAS export
2. Nextcloud
3. Everything else

## Debugging

```bash
# Check pending background jobs
docker exec -it nextcloud-db mariadb -u root -p nextcloud \
    -e "SELECT COUNT(*) FROM oc_jobs WHERE last_run = 0;"

# Manually run cron
time docker exec nextcloud php /var/www/html/cron.php
```
