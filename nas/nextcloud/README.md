# Nextcloud
https://github.com/nextcloud/server

File sharing


## Setup
Make sure to update the `.env` with your variables, because a lot of the configuration settings are only applied on the initial run.
- There is a way to install Nextcloud curing an Ubuntu Server installation, but I'm not sure how to configure it with all of the things that must be configured before the first time it runs.

### Housekeeping
Any command that starts with occ can be run from the host by using `docker exec -u www-data nextcloud php /var/www/html/occ` before the occ command you want to run.

#### Migrate mimetypes to better handle certain file types (may be required after each major update)
- `docker exec -u www-data nextcloud php /var/www/html/occ maintenance:repair --include-expensive`

#### Add new indicies (may be required after each major update)
- `docker exec -u www-data nextcloud php /var/www/html/occ db:add-missing-indices`

#### Cron job
Nextcloud wants you to run cron.php every 5 minutes.
- Add a cron job to the docker host running Nextcloud
- `sudo crontab -e`
- Append to the end of the file
- `*/5 * * * * docker exec -u www-data nextcloud php /var/www/html/cron.php`
- Save
- Verify in Nextcloud Administration -> Basic settings
- Nextcloud should switch itself from `AJAX` to `Cron (Recommended)`

#### Set maintenance window
Nextcloud’s maintenance_window_start value is in UTC hours (0–23), not local time.
- `docker exec -u www-data nextcloud php /var/www/html/occ config:system:set maintenance_window_start --type=integer --value=8`

### Enable exteranl storage
- Login as admin
- Go to `/settings/apps/featured`
  - Click on top right profile icon
  - Select Apps
  - Click on featured on the left
- Scroll down to `External storage`
- Click Enable

### Add S3 (MinIO)
Note: BEFORE adding this, if you are loading a large amount of files, it may be easier to upload directly to MinIO rather than let Nextcloud sync it. It also struggled to sync any files larger than 10GB and long paths, EG node_modules (maybe nuke those before backing up).
- Go to `settings/admin/externalstorages`
  - Click on top right profile icon
  - Select Administrative settings
  - Click on `External storage`
- Add AmazonS3 type, using Access key
  - Set Bucket to "nextcloud"
  - Set Hostname to "minio"
  - Set Port to 9000
  - Uncheck "Enable SSL"
  - Check "Enable Path Style"
  - Copy minio_access_key
  - Copy minio_secret_key

### Auto sync from phone
- Turn on auto upload
- Configure the target path to be in S3 (if you like)
<!-- #### Non-audio/video file sync
December 2024 Google revoked "All file access" permissions for the Nextcloud app.
- Download FolderSync (or use F-Droid?)
- Add Nextcloud credentials
- Add folder sync
- Setup schedule
- Turn on instant upload -->


## Maintenance
- Enter maintenance mode: `docker exec -u www-data nextcloud php occ maintenance:mode --on`
- Exit: `docker exec -u www-data nextcloud php occ maintenance:mode --off`

### Restart servers
Order you'd likely want to boot up:
- TrueNAS
- MinIO
- Nextcloud
- Rest can start before/after, doesn't matter


## Debugging
#### Check background processes
- Load into the mariadb container
- `docker exec -it nextcloudsql mysql -u root -p`
- Check how many pending jobs there are
- `SELECT COUNT(*) FROM nextcloud.oc_jobs WHERE last_run = 0;`

#### Manually run cron.php
- Run with time tracking
- `time docker exec -u www-data nextcloud php /var/www/html/cron.php`
