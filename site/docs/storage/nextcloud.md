---
sidebar_position: 3
---

# Nextcloud

- Source: https://github.com/nextcloud/server
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: ownCloud, Seafile, Syncthing

File sharing and sync — Dropbox/Google Drive alternative.

## Features

- **File Sync & Sharing**: Desktop and mobile sync clients with granular sharing and permissions
- **Collaborative Editing**: Real-time document editing via [Collabora](./collabora)
- **Calendar & Contacts**: CalDAV/CardDAV server compatible with any standard client
- **External Storage**: Mount S3, FTP, SFTP, and other backends as Nextcloud folders
- **App Store**: 300+ apps for notes, email, photos, video calls, and more
- **Talk**: Built-in video calls, chat, and screen sharing without a third-party service

## Setup

Update `.env` with your variables before first run — many configuration settings are only applied on initial startup.

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
