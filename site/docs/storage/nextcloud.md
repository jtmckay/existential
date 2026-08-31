---
sidebar_position: 3
---

# Nextcloud

- Source: https://github.com/nextcloud/server
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: ownCloud, Seafile, Syncthing

File sharing and sync — Dropbox/Google Drive alternative.

## Setup

Most of Nextcloud's environment variables are read by the installer on the **first** run only,
and ignored afterwards — so set what you care about before you bring it up the first time.

The exception is the domain, because that one has to be able to change. `EXIST_DOMAIN` is the one
knob you move to relocate the whole stack, and the installer would otherwise freeze Nextcloud at
whatever name it saw first — leaving it answering *"Access through untrusted domain"* while every
other service followed the new name. A `before-starting` hook re-applies `trusted_domains`,
`overwritehost`, `overwriteprotocol`, `overwrite.cli.url` and `trusted_proxies` from the
environment on every start, so changing `EXIST_DOMAIN` and re-running is enough. It logs only
when something actually changed.

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

1. Enable **External storage** app: `/settings/apps/featured`
2. Go to **Administration settings → External storage**
3. Add AmazonS3 type with Access key:
   - Bucket: `nextcloud`
   - Hostname: `minio`
   - Port: `9000`
   - Uncheck "Enable SSL"
   - Check "Enable Path Style"
   - Paste MinIO access key and secret key

## Maintenance

```bash
# Enter maintenance mode
docker exec -u www-data nextcloud php occ maintenance:mode --on

# Exit maintenance mode
docker exec -u www-data nextcloud php occ maintenance:mode --off
```

### Restart order

1. TrueNAS
2. MinIO
3. Nextcloud
4. Everything else

## Debugging

```bash
# Check pending background jobs
docker exec -it nextcloudsql mysql -u root -p
SELECT COUNT(*) FROM nextcloud.oc_jobs WHERE last_run = 0;

# Manually run cron
time docker exec -u www-data nextcloud php /var/www/html/cron.php
```
