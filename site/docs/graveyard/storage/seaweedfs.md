---
sidebar_position: 3
---

# SeaweedFS

- Source: https://github.com/seaweedfs/seaweedfs
- License: [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Status: RIP — replaced by [Nextcloud](../../storage/nextcloud) on its own

## Why it left

Nothing was wrong with SeaweedFS. The object store itself was the problem: it existed
to produce file events, and it cost a second copy of everything to do it.

Files had to be *in* the bucket to fire, so `workspace/` was bisynced into it every
ten minutes, with a live pull processor for the other direction and conflict copies
when both sides moved. The bucket stored files as needles inside its own volume
files, so none of it was browsable on disk. And the only thing reading those files
back out was `file-processor` — through Nextcloud's WebDAV, not S3.

Nextcloud 30+ ships `webhook_listeners`, which posts file events on its own. So the
workspace became a volume Nextcloud serves as Local storage, the desktop client does
the syncing, and every upload through Nextcloud is the event. There is one copy, it
is plain files, and the stack's own writes fire nothing, so the loop-breaker that
`workspace/ai/` needed came for free.

## What the swap changed

| Gone | Replaced by |
|---|---|
| `nas/seaweedfs`, its Caddy hosts and Dashy tile | nothing — Nextcloud was already there |
| `workspace-sync` (bisync every 10 minutes) | the Nextcloud desktop client |
| `workspace-pull` file processor | nothing — there is no second copy to pull into |
| `s3-router`, the `/s3` webhook route | `file-router`, the `/files` route |
| `notification.toml` subscription | the `nextcloud-file-events` migration |
| the `outbox-relay` file processor | the `outbox-relay` routine, polling every minute |
| the `/S3` external storage mount | the `/workspace` Local mount |

## If you still want it

The service files are kept under `graveyard/seaweedfs/`. Nothing in the stack talks
to it any more, so re-enabling it means restoring the routing by hand.
