---
sidebar_position: 2
---

# SeaweedFS

- Source: https://github.com/seaweedfs/seaweedfs
- License: [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: Ceph, Garage, Amazon S3, [MinIO](../graveyard/storage/minio) (retired)
- UI: `https://seaweedfs.<domain>` (the Admin UI — buckets, S3 identities and policies,
  lifecycle rules, volume health)

S3-compatible object storage. Provides an S3 interface to all files — replaceable with Amazon
S3 if needed. It replaced MinIO, whose open-source repository was archived in February 2026;
see [the graveyard entry](../graveyard/storage/seaweedfs) for what changed.

One container runs the whole thing. `weed mini` starts the master, volume server, filer, S3
gateway, WebDAV gateway and Admin UI in a single process, which is the right shape for one
homelab node.

## Benefits of S3 Interface

- Uniform file API across all services
- File-event notifications for automations — this stack wires them to a plain HTTP webhook
  (see [File Event Hooks](#file-event-hooks) below), not a message queue
- Swap backing storage without changing integrations

## Connect to Nextcloud

Automatic — nothing to do.

SeaweedFS creates the `nextcloud` bucket itself on startup (its `-bucket` flag), and Nextcloud
mounts it as external storage at **/S3** (a folder in Files, shared with every user). Because
it is an external-storage mount rather than primary object storage, objects keep their real
filenames, which is what the [File Processor](../decree/file-change-processing) pipeline
matches on.

Nextcloud does **not** use the root credentials. `nas/seaweedfs/s3.json` declares a second
identity named `nextcloud`, scoped to that one bucket with `Read`/`Write`/`List`/`Tagging`, and
Nextcloud authenticates as that identity. The root pair stays what it should be: the Admin UI
login and the credential the routines run as. The access key and secret render from
`EXIST_S3_NEXTCLOUD_ACCESS_KEY` / `EXIST_S3_NEXTCLOUD_SECRET_KEY` into both
`nas/seaweedfs/s3.json` and `nas/nextcloud/.env`, so the two sides cannot drift — and
`nas/seaweedfs/exist.test.sh` probes that identity specifically, so if they ever do, the test
says so instead of the `/S3` folder silently listing nothing.

To use a different bucket, change the `-bucket` flag in `nas/seaweedfs/docker-compose.exist.yml`,
the `actions` scoping in `s3.json`, `path_prefixes` in `notification.toml`, and
`NEXTCLOUD_S3_BUCKET` in `nas/nextcloud/.env`. To disable the mount, blank `NEXTCLOUD_S3_KEY`.

## Two volumes, and why

`seaweedfs_data` holds nothing but append-only needle files, so it is safe on an NFS export and
is declared `nfs: true`. `seaweedfs_meta_data` holds three embedded databases — the master's
raft state, the filer's LevelDB store, and the Admin UI's own config — and is declared
`db: true`, which the volume rules forbid from ever landing on NFS.

This split is why `nas/seaweedfs/exist.initial.sh` exists: `weed` checks those metadata
directories for writability at boot and dies on a missing one, and `generate-compose.ts` creates
only the top-level volume directory.

## workspace/ lives in the same bucket

With SeaweedFS enabled, the repo-root `workspace/` directory — the agent's knowledgebase, see
[Getting Started → Workspace](../getting-started#workspace) — bidirectionally syncs with the
`workspace/` subfolder of this same `nextcloud` bucket, via the `workspace-sync` routine
(`rclone bisync`, every 10 minutes). Because it's the same bucket Nextcloud mounts at `/S3`,
editing a file on this machine, in the bucket directly, or in Nextcloud's web UI all converge —
there's no second bucket or second mount to keep in step.

Two more pieces make this self-configuring, with nothing to set up by hand on a fresh install
(both Core-default when SeaweedFS is enabled):

- **`nextcloud-rclone-remote` migration** — configures the rclone WebDAV remote that file
  downloads go through, from the already-rendered Nextcloud admin credentials.
- **`workspace-pull` file processor** — the live half: a bucket- or Nextcloud-side edit shows
  up in `workspace/` in about a second, instead of waiting for the next `workspace-sync` tick.

Because the bucket is shared with Nextcloud's own storage, *every* Nextcloud file event fires
the webhook too, not just `workspace/` ones — see
[File Processor](../decree/file-change-processing) for how `PATTERN` matching keeps that from
mattering.

## File Event Hooks

SeaweedFS POSTs file events to the Decree webhook to trigger automations when files are created,
updated, renamed or deleted. See [File Processor](../decree/file-change-processing) for full
setup instructions.

One structural difference from MinIO is worth knowing, because it is what deleted a routine and
a migration: SeaweedFS does not implement `PutBucketNotificationConfiguration` at all. There is
no per-bucket subscription to make. Instead the whole subscription lives in
`nas/seaweedfs/notification.toml`, which the filer reads at boot — endpoint, bearer token, which
event types, and which paths:

```toml
[notification.webhook]
enabled = true
endpoint = "http://automation-webhook:8801/s3"
event_types = ["create", "update", "delete", "rename"]
path_prefixes = ["/buckets/nextcloud"]
```

Two consequences:

- **Events are filer paths, not bucket/key pairs.** `key` arrives as
  `/buckets/nextcloud/workspace/report.pdf`. `s3-router` strips the `/buckets/` prefix and then
  splits off the bucket exactly as before, so `PATTERN`s did not change.
- **Directories raise events of their own**, carrying `is_directory: true`. MinIO had no
  directory concept and never did this; `s3-router` drops them.

`path_prefixes` is what scoping looks like here. It ships watching the whole `nextcloud` bucket,
which is what MinIO effectively did. Narrowing it to `["/buckets/nextcloud/workspace"]` is a
one-line change — but it would also stop the Telegram ingest and WhisperX transcription flows,
which watch other prefixes of the same bucket.

## VM Note

If you see errors starting this container, try changing the VM CPU type from `KVM` to `host` in
Proxmox.
