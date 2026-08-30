---
sidebar_position: 2
---

# MinIO

- Source: https://github.com/minio/minio
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: Ceph, SeaweedFS, Garage, Amazon S3

S3-compatible object storage. Provides an S3 interface to all files — replaceable with Amazon S3 if needed.

## Benefits of S3 Interface

- Uniform file API across all services
- Native hooks for automations (integrates with NSQ/RabbitMQ)
- Swap backing storage without changing integrations

## Connect to Nextcloud

Automatic — nothing to do.

On a first `docker compose up -d`, the `01-create-nextcloud-bucket` migration creates the
`nextcloud` bucket, and Nextcloud mounts it as external storage at **/S3** (a folder in Files,
shared with every user). Because it is an external-storage mount rather than primary object
storage, objects keep their real filenames, which is what the
[File Processor](../decree/file-change-processing) pipeline matches on.

Both halves authenticate with the MinIO root credentials from `nas/minio/.env`, so there is no
separate access key to create. To use a different bucket, change `BUCKET` in
`nas/minio/decree/migrations/01-create-nextcloud-bucket.md` and `NEXTCLOUD_S3_BUCKET` in
`nas/nextcloud/.env` to match. To disable the mount, blank `NEXTCLOUD_S3_KEY`.

## File Event Hooks

MinIO can POST S3 events to the Decree webhook to trigger automations when files are created, updated, or deleted. See [File Processor](../decree/file-change-processing) for full setup instructions.

## VM Note

If you see errors starting this container, try changing the VM CPU type from `KVM` to `host` in Proxmox.
