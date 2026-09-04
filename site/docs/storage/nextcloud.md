---
sidebar_position: 3
---

# Nextcloud

- Source: https://github.com/nextcloud/server
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: ownCloud, Seafile, Syncthing

File sharing and sync — Dropbox/Google Drive alternative.

Redis (`nas/redis`) is a hard dependency, not an optional add-on: file locking and PHP sessions
are wired to it unconditionally, so enabling Nextcloud without Redis leaves it up but broken in
ways `/status.php` cannot see. Enable both together.

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

## External Storage (MinIO/S3)

Automatic on a fresh install: `hooks/post-installation/01-minio-external-storage.sh` mounts the
`nextcloud` MinIO bucket as an "S3" folder the moment `occ maintenance:install` finishes, using
the scoped service identity minio's own migrations create (never the console login). If MinIO
was enabled *after* Nextcloud already existed — that hook only runs once, at first install — add
it by hand:

1. Enable **External storage** app: `/settings/apps/featured`
2. Go to **Administration settings → External storage**
3. Add AmazonS3 type with Access key:
   - Bucket: `nextcloud`
   - Hostname: `minio`
   - Port: `9000`
   - Uncheck "Enable SSL"
   - Check "Enable Path Style"
   - Paste MinIO access key and secret key (`nas/minio/.env`, `MINIO_NEXTCLOUD_ACCESS_KEY`/`_SECRET_KEY`)

## Collabora (office document editing)

Nextcloud does not talk to `nas/collabora` out of the box — the `richdocuments` app has to be
installed and pointed at it. `automation-examples/migrations/22-nextcloud-richdocuments.md`
does this the same way the MinIO bucket gets created: copy it to
`automation/migrations/` and restart `decree` to activate. It also sets
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
2. MinIO
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
