---
sidebar_position: 2
---

# MinIO

- Source: https://github.com/minio/minio
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: Ceph, SeaweedFS, Garage, Amazon S3
- UI: `https://minio.<domain>` (the admin console — bucket browsing, users, event
  notification targets)

S3-compatible object storage. Provides an S3 interface to all files — replaceable with Amazon S3 if needed.

## Benefits of S3 Interface

- Uniform file API across all services
- Native S3 event notifications for automations — this stack wires them to a plain HTTP
  webhook (see [File Event Hooks](#file-event-hooks) below), not a message queue
- Swap backing storage without changing integrations

## Connect to Nextcloud

Automatic — nothing to do.

On a first `docker compose up -d`, the `20-minio-create-nextcloud-bucket` migration creates the
`nextcloud` bucket, and Nextcloud mounts it as external storage at **/S3** (a folder in Files,
shared with every user). Because it is an external-storage mount rather than primary object
storage, objects keep their real filenames, which is what the
[File Processor](../decree/file-change-processing) pipeline matches on.

Nextcloud does **not** use the MinIO root credentials. The
`21-minio-create-nextcloud-service-account` migration creates a MinIO user named `nextcloud`,
attaches a `nextcloud-rw` policy scoped to that one bucket, and Nextcloud authenticates as that
identity. The root pair stays what it should be: the console login, and the admin credential the
two migrations themselves run as. The access key and secret render from
`EXIST_MINIO_NEXTCLOUD_ACCESS_KEY` / `EXIST_MINIO_NEXTCLOUD_SECRET_KEY` into both
`nas/minio/.env` and `nas/nextcloud/.env`, so the two sides cannot drift.

To use a different bucket, change `BUCKET` in both migrations and `NEXTCLOUD_S3_BUCKET` in
`nas/nextcloud/.env` to match — the migration reads the credentials from env vars named after the
bucket (`BUCKET: media` → `MINIO_MEDIA_ACCESS_KEY`). To disable the mount, blank
`NEXTCLOUD_S3_KEY`.

### Upgrading an install that predates the service account

The external-storage mount is configured once, right after Nextcloud installs, so an existing
install still holds the root credentials. Rendered files are never re-rendered either, so nothing
changes on its own. To move an existing install over:

1. Add the two keys to `.env.shared`, `nas/minio/.env` and `nas/nextcloud/.env` by hand — the
   same access key on both sides, and a fresh secret (`openssl rand -hex 16`).
2. Copy `automation-examples/migrations/21-minio-create-nextcloud-service-account.md`
   into `automation/migrations/` and let the `decree` daemon apply it. Confirm with
   `docker logs automation`.
3. Point the existing mount at the new identity:

```bash
docker exec -u www-data nextcloud php occ files_external:list        # note the /S3 mount id
docker exec -u www-data nextcloud php occ files_external:config <id> key    nextcloud
docker exec -u www-data nextcloud php occ files_external:config <id> secret <the new secret>
```

Step 3 must come after step 2 — the identity has to exist in MinIO before Nextcloud tries it.

## workspace/ lives in the same bucket

With MinIO enabled, the repo-root `workspace/` directory — the agent's knowledgebase, see
[Getting Started → Workspace](../getting-started#workspace) — bidirectionally syncs with the
`workspace/` subfolder of this same `nextcloud` bucket, via the `workspace-sync` routine
(`rclone bisync`, every 10 minutes). Because it's the same bucket Nextcloud mounts at `/S3`,
editing a file on this machine, in MinIO directly, or in Nextcloud's web UI all converge —
there's no second bucket or second mount to keep in step.

Three more pieces make this self-configuring, with nothing to set up by hand on a fresh
install (all Core-default when MinIO is enabled):

- **`nextcloud-rclone-remote` migration** — configures the rclone WebDAV remote that file
  downloads go through, from the already-rendered Nextcloud admin credentials.
- **`minio-bucket-webhook` routine** — subscribes the bucket to the Decree webhook (see
  below), chained automatically by `workspace-sync` itself right after its first successful
  sync, never manually — subscribing before that first bulk upload would turn it into one
  event per file arriving at once.
- **`workspace-pull` file processor** — the live half: a MinIO- or Nextcloud-side edit shows
  up in `workspace/` in about a second, instead of waiting for the next `workspace-sync` tick.

Because the bucket is shared with Nextcloud's own storage, subscribing it to the webhook means
*every* Nextcloud file event fires it too, not just `workspace/` ones — see
[File Processor](../decree/file-change-processing) for how `PATTERN` matching keeps that from
mattering.

## File Event Hooks

MinIO can POST S3 events to the Decree webhook to trigger automations when files are created, updated, or deleted. See [File Processor](../decree/file-change-processing) for full setup instructions.

## VM Note

If you see errors starting this container, try changing the VM CPU type from `KVM` to `host` in Proxmox.
