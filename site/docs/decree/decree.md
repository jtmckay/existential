---
sidebar_position: 1
---

# Decree

Decree is the automation engine at the heart of the Existential stack. It processes files, integrates with cloud storage via rclone, reads from S3/MinIO, and connects to external services like Gmail.

## Running Decree

### Connect to a running container

```bash
docker compose run decree bash
```

### One-off run (without daemon)

```bash
docker compose run --rm decree decree process
```

## Integrations

Gmail and rclone are configured through interactive setup scripts. See [Integrations](../integrations/) for setup instructions.

## Configure S3

Set your MinIO (or AWS S3) credentials in `services/decree/.env`:

```bash
S3_ENDPOINT=http://minio:9000
S3_ACCESS_KEY=your_access_key
S3_SECRET_KEY=your_secret_key
S3_BUCKET=your_bucket
```
