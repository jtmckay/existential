---
sidebar_position: 3
---

# rclone

Configures rclone for remote file storage access inside Decree. Supports any rclone-compatible backend: Nextcloud, Dropbox, Google Drive, S3, and more.

## Setup

```bash
./existential.sh setup rclone
```

Opens an interactive rclone config session inside the `decree-adhoc` container — no host rclone install needed. Add as many remotes as you need and choose `q` when done.

Config is saved to `services/decree/secrets/rclone/rclone.conf` and loaded by the container at runtime.
