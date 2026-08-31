---
routine: minio-bucket
BUCKET: workspace
---

Create the `workspace` bucket in MinIO.

This is the bucket the `workspace-sync` routine mirrors `workspace/` into, so
that edits you make by hand become S3 events the decree webhook can route to
matched file processors.

The bucket on its own does nothing. Two more steps turn it into a trigger, and
their ORDER matters — see the auto-workspace-agent quest:

  1. Sync once, before subscribing, so the initial upload of the whole workspace
     does not arrive as one event per file:

       printf -- '---\nroutine: workspace-sync\n---\n' \
         > services/decree/decree-backup/inbox/sync-once.md

  2. Then subscribe the bucket to the webhook:

       docker exec minio mc event add minio/workspace \
         arn:minio:sqs::DECREE:webhook --event put,delete

Safe to re-run — an existing bucket is left alone. Copy to
services/decree/decree/migrations/ to activate.
