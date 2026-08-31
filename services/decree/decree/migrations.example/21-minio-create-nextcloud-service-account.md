---
routine: minio-service-account
BUCKET: nextcloud
---

Create the `nextcloud` MinIO user and scope it to the `nextcloud` bucket.

Nextcloud authenticates to MinIO with this identity rather than the root
credentials, so the console login is never handed to a service and Nextcloud
holds read/write on one bucket instead of admin on the whole server. The access
key and secret come from the decree container's MINIO_NEXTCLOUD_ACCESS_KEY /
MINIO_NEXTCLOUD_SECRET_KEY env, rendered from the same shared pair
nas/nextcloud/.env reads — see nas/minio/.env.

Runs after 20-minio-create-nextcloud-bucket: the policy names the bucket, and MinIO
accepts a policy for a bucket that does not exist yet, but keeping the order
means the identity is never valid before its target is.

Change BUCKET to scope a different bucket; the credential env vars are named
after it (BUCKET: media reads MINIO_MEDIA_ACCESS_KEY). Keep it in step with
NEXTCLOUD_S3_BUCKET in nas/nextcloud/.env.

Safe to re-run — an existing policy is left alone and the user's secret is reset
to the rendered value. Copy to services/decree/decree/migrations/ to activate
(the Core quest does this for you).
