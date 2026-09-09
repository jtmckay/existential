---
sidebar_position: 2
---

# MinIO

- Source: https://github.com/minio/minio
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Status: RIP — replaced by [SeaweedFS](../../storage/seaweedfs)
- Alternatives: SeaweedFS, Ceph, Garage, Amazon S3

## Why it left

MinIO stripped the web console out of the community edition in May 2025 — bucket
management, IAM, lifecycle rules and audit logging all moved to the paid product
overnight, which is why `minio.<domain>` had so little left in it. In December 2025
the open-source project went into maintenance mode, and in February 2026 the
repository was archived outright: no issues, no pull requests, no further releases.

The stack was pinned to `RELEASE.2025-09-07T16-13-09Z`, which is effectively the
last one there will ever be. That is not a tenable position for the one service
holding every file in `workspace/` and backing Nextcloud's `/S3` mount.

SeaweedFS replaced it: Apache-2.0 rather than AGPL-3, weekly releases, and an Admin
UI that still has the IAM policy editor and lifecycle rules MinIO took away.

## What the swap actually changed

Less than expected, because the pipeline was decoupled at the same time. The
automation layer is now named for the *role* (`s3-router`, `automation/lib/s3.sh`,
the `/s3` webhook endpoint, `S3_*` env) rather than the product, so the store itself
is named in only two places.

Three routines and two migrations were deleted rather than ported:

| Gone | Why |
|---|---|
| `minio-bucket` + its migration | SeaweedFS pre-creates buckets with its own `-bucket` flag |
| `minio-service-account` + its migration | Identities are a static rendered `s3.json` |
| `minio-bucket-webhook` | The subscription is a config file read at boot, not an admin-API call |

The `mc` client came out of the decree image with them, as did the
`latest_hub_release` version-check path, which existed solely because MinIO stopped
publishing `RELEASE.*` tags to Docker Hub while still cutting GitHub releases.

## If you still want it

The service files are kept under `graveyard/minio/`: `docker-compose.yml.example`,
`.env.example`, and its `exist.test.sh`. Nothing was deleted — but it is no longer
wired into `./existential.sh`, Caddy, Dashy, or the quests, and the routines it
depended on are gone, so re-enabling it means restoring those by hand.

Existing data is untouched. The bucket contents stay at `volumes/minio_data/` until
you remove them yourself. Note that MinIO's single-drive layout stores each object
as a directory of `xl.meta` plus part files, so that directory is not readable
without MinIO running — copy anything you want out with `rclone` while it is still
up.
