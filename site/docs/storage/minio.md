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

1. Go to `http://docker_host_ip:9001/login`
2. Create an access key named `Nextcloud`
3. Save the Access Key and Secret Key for use with Nextcloud

## File Event Hooks

MinIO can POST S3 events to the Decree webhook to trigger automations when files are created, updated, or deleted. See [File Processor](../decree/file-change-processing) for full setup instructions.

## VM Note

If you see errors starting this container, try changing the VM CPU type from `KVM` to `host` in Proxmox.
