---
sidebar_position: 1
---

# Storage Overview

Pick and choose components to use. For example: use Google Drive for files and skip TrueNAS and Nextcloud.

## What's Important

- **NFS** — Container persistence
- **Nextcloud** — Desktop and mobile app file sync (image/video upload, etc.), and the file
  events automations react to

## Components

| Service                     | Purpose                | Alternatives                    |
| --------------------------- | ---------------------- | ------------------------------- |
| [Nextcloud](./nextcloud)    | File sharing & sync    | Dropbox, OneDrive, Google Drive |
| [Collabora](./collabora)    | Nextcloud document editor | OnlyOffice                   |
| TrueNAS                     | File redundancy & NFS  | —                               |
