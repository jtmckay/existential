---
sidebar_position: 3
---

# rclone

Configures rclone for remote file storage access inside Decree. Supports any rclone-compatible backend: Nextcloud, Dropbox, Google Drive, S3, and more.

## Setup

```bash
./existential.sh run rclone
```

Opens an interactive rclone config session inside the `existential-adhoc` container — no host rclone install needed. Add as many remotes as you need and choose `q` when done.

Config is saved to `automation/secrets/rclone/rclone.conf` and loaded by the container at runtime.

:::note[The `nextcloud` remote configures itself]
If MinIO is enabled, a `nextcloud` remote (WebDAV, using the already-rendered admin
credentials) is set up for you automatically by the `nextcloud-rclone-remote` migration —
it's what `file-processor` downloads through for anything reached via Nextcloud's `/S3`
external storage. No need to add it here unless you're pointing it somewhere else.
:::
