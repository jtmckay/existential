---
sidebar_position: 1
---

# Object Storage Alternatives

## Checklist

- S3 API, path-style, usable as Nextcloud external storage
- File events that fire for writes from *every* direction, not just the app's own
- Still maintained

## Evaluated

- [SeaweedFS](../../storage/seaweedfs) — active stack
- [MinIO](./minio) — RIP the open-source project was archived in February 2026
- Ceph — a distributed filesystem first; far more machine than one homelab node needs
- Garage — good and genuinely simple, but no event notifications, which is the whole
  point of the object store here
- Amazon S3 — works, but the file-event pipeline would then depend on the internet
