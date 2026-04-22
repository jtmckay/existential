---
sidebar_position: 1
---

# Storage Overview

Pick and choose components to use. For example: use Google Drive for files and skip TrueNAS, MinIO, Redis, and Nextcloud.

## What's Important

- **NFS** — Container persistence
- **S3 API** — File persistence and automation hooks
- **Nextcloud** — Desktop and mobile app file sync (image/video upload, etc.)

## Components

| Service                     | Purpose                | Alternatives                    |
| --------------------------- | ---------------------- | ------------------------------- |
| [MinIO](./minio)            | S3-compatible file API | AWS S3                          |
| [Nextcloud](./nextcloud)    | File sharing & sync    | Dropbox, OneDrive, Google Drive |
| [Collabora](./collabora)    | Nextcloud document editor | OnlyOffice                   |
| [Redis](./redis)            | In-memory cache        | —                               |
| TrueNAS                     | File redundancy & NFS  | —                               |
