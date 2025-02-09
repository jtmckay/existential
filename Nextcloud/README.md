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
