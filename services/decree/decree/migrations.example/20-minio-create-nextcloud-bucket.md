---
routine: minio-bucket
BUCKET: nextcloud
---

Create the `nextcloud` bucket in MinIO.

Nextcloud mounts this bucket as an external storage folder at /S3 — see
nas/nextcloud/hooks/post-installation/01-minio-external-storage.sh, which runs
once on the Nextcloud side. The two halves are independent: Nextcloud can be
configured before this bucket exists, and this bucket is useful without it.

Change BUCKET to use a different name; keep it in step with NEXTCLOUD_S3_BUCKET
in nas/nextcloud/.env.

Safe to re-run — an existing bucket is left alone. Copy to
services/decree/decree/migrations/ to activate (the Core quest does this for you).
