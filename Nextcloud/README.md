# Nextcloud
File sharing

## Setup
Make sure to update the `.env` with your variables, because a lot of the configuration settings are only applied on the initial run.

### Trusted domains
Add domains to the list in `nextcloud_data/config/config.php`

### Enable exteranl storage
- Login as admin
- Go to `/settings/apps/featured`
  - Click on top right profile icon
  - Select Apps
  - Click on featured on the left
- Scroll down to `External storage`
- Click Enable

### Add S3 (MinIO)
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
#### Non-audio/video file sync
December 2024 Google revoked "All file access" permissions for the Nextcloud app.
- Download FolderSync (or use F-Droid?)
- Add Nextcloud credentials
- Add folder sync
- Setup schedule
- Turn on instant upload

### Task app from Nextcloud
Doesn't support recurring tasks. Will use task.org solution instead.

### Cookbook app from Nextcloud
Testing this one out, and sharing the folder to hopefully keep recipes in sync with multiple people.

## Maintenance
- Enter maintenance mode: `docker exec -u www-data nextcloud php occ maintenance:mode --on`
- Exit: `docker exec -u www-data nextcloud php occ maintenance:mode --off`

Still working on scheduling maintenance automatically.

### Cron
Nextcloud wants you to run cron.php every 5 minutes.
- Add a cron job to the docker host running Nextcloud
- `sudo crontab -e`
- Append to the end of the file
- `*/5 * * * * docker exec -u www-data nextcloud php /var/www/html/cron.php`
- Save
- Verify in Nextcloud Administration -> Basic settings
- Nextcloud should switch itself from `AJAX` to `Cron (Recommended)`

### Restart servers
Order you'd likely want to boot up:
- TrueNAS
- MinIO
- Nextcloud
- Rest can start before/after, doesn't matter
