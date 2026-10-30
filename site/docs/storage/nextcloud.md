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

- Most environment variables are read only on the **first** start. Set them before then.
- `trusted_domains` is re-applied from `EXIST_DOMAIN` on every start (a `before-starting` hook),
  so changing the domain doesn't leave Nextcloud on "Access through untrusted domain".
- `overwritehost`, `overwriteprotocol`, `overwrite.cli.url` and `trusted_proxies` are read from the
  environment on every request, so they follow `EXIST_DOMAIN` too.

## On a NAS

`nextcloud_data`, `nextcloud_config_data`, `nextcloud_custom_apps_data` and
`nextcloud_themes_data` can live on the NAS ([Storage](./#a-nas-for-the-bulk-files)); the
database never does. `nextcloud_data` holds Nextcloud's own layout (`<user>/files/`,
`appdata_*`, `nextcloud.log`), so give `EXIST_NFS_PATH_NEXTCLOUD_DATA` an empty folder, never a
share of files you already have: Nextcloud would not index them, and its own files would land
among them.

To see a share of existing files in Nextcloud, add it as External storage (the app is already
on). Nextcloud has no NFS backend, so use the share's SMB side: **Administration settings →
External storage**, backend **SMB/CIFS**, host the NAS, the share's name and a login. From the
host:

```bash
docker exec nextcloud php /var/www/html/occ files_external:create /Photos smb password::password \
    -c host=<nas-address> -c share=<share> -c user=<user> -c password=<password>
```

## Cache

`nextcloud-redis` (`redis:8.10.1-alpine3.23`, licensed
[RSALv2 / SSPLv1 / AGPLv3](https://redis.io/legal/licenses/); for commercial hosting pick AGPLv3
or RSALv2):

- Nextcloud's file locking, distributed cache and PHP sessions. Required, so it lives in
  Nextcloud's compose file.
- Only Nextcloud uses it; other services have their own redis.
- No volume (`--save ""`). Losing it costs a re-login. Nothing to back up.
- No `maxmemory`: at its 128M limit Docker restarts it.

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

`nextcloud-cron` runs `cron.php` every minute and delivers webhooks; its first run switches
**Basic settings** from `AJAX` to `Cron`. Nothing to add to the host's crontab.

### Set maintenance window (UTC)

```bash
docker exec nextcloud php /var/www/html/occ config:system:set maintenance_window_start --type=integer --value=8
```

## The workspace folder

`hooks/before-starting/02-workspace.sh` mounts the `workspace_data` volume as a **Local**
external storage at `/workspace`, applicable to every user. Sync that folder with the desktop client and you are editing the
same tree hermes and code-server see. See [Getting Started → Workspace](../getting-started#workspace).

- Nextcloud runs as `EXIST_PUID`, not `www-data`, because every writer of the volume must be the
  same uid.
- Workspace automations don't need Nextcloud: [File Handlers](../decree/file-handlers) see every
  change. Uploads anywhere in Nextcloud can also fire a file event:
  [File Processor](../decree/file-change-processing).

## Collabora (office document editing)

`./existential.sh flow on office-documents` installs the `richdocuments` app, points it at
Collabora, and limits `wopi_allowlist` to the `exist` subnet (blank would allow any IP).

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

CalDAV is always on; the Calendar app (`/apps/calendar`) isn't. `./existential.sh flow on
calendar` installs it.

To do it by hand instead:

```bash
docker exec nextcloud php /var/www/html/occ app:install calendar
```

### Indexed by OpenViking, answerable by hermes

The flow's `calendar-extract` cron writes each event, from the recent past to
`CALENDAR_EXTRACT_FUTURE_DAYS` ahead, as a note in `workspace/ai/calendar/<calendar>/`. OpenViking
indexes it, so hermes can answer "what's on my calendar".

- Full refresh: a cancelled event's note disappears on the next run.
- CalDAV details: `automation/scripts/calendar_extract.sh` (tested on nextcloud:34.0.3, recurring
  events included).

## Maintenance

```bash
# Enter maintenance mode
docker exec nextcloud php /var/www/html/occ maintenance:mode --on

# Exit maintenance mode
docker exec nextcloud php /var/www/html/occ maintenance:mode --off
```

Nextcloud's update check and `survey_client` app are off (the check sends install time, PHP
version and user count). `hooks/before-starting/03-no-phone-home.sh` re-applies this on every
start. To update, bump the image tag in `docker-compose.exist.yml`.

### Restart order

Only when `nextcloud_data` is on the NAS: the NAS first, then Nextcloud. Compose mounts the
export when the container starts, so a NAS that is down stops Nextcloud from starting; start it
again once the NAS is up.

## Debugging

```bash
# Check pending background jobs
docker exec -it nextcloud-db mariadb -u root -p nextcloud \
    -e "SELECT COUNT(*) FROM oc_jobs WHERE last_run = 0;"

# Manually run cron
time docker exec nextcloud php /var/www/html/cron.php
```
