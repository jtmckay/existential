---
sidebar_position: 2
---

# MinIO

- Source: https://github.com/minio/minio
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: Ceph, SeaweedFS, Garage, Amazon S3

S3-compatible object storage. Provides an S3 interface to all files — replaceable with Amazon S3 if needed.

## Features

- **S3-Compatible API**: Works with any S3 SDK, CLI, or tool — swap for AWS S3 without changing integrations
- **High Performance**: Designed for throughput with parallel read/write across drives
- **Event Notifications**: Publish file events to webhooks, Kafka, AMQP, or NATS for automations
- **Web Console**: Browser-based UI for bucket management, access keys, and policies
- **IAM-Style Access Control**: Per-bucket policies and scoped access keys for multi-tenant use
- **Erasure Coding**: Configurable data redundancy to survive drive failures

## Benefits of S3 Interface

- Uniform file API across all services
- Native hooks for automations (integrates with NSQ/RabbitMQ)
- Swap backing storage without changing integrations

## Connect to Nextcloud

1. Go to `http://docker_host_ip:9001/login`
2. Create an access key named `Nextcloud`
3. Save the Access Key and Secret Key for use with Nextcloud

## File Event Hooks

MinIO can POST S3 events to the Decree webhook to trigger automations when files are created, updated, or deleted. See [File Change → Process](../decree/file-change-processing) for full setup instructions.

## VM Note

If you see errors starting this container, try changing the VM CPU type from `KVM` to `host` in Proxmox.
