---
cron: "*/10 * * * *"
routine: workspace-sync
---

Mirror `workspace/` into the `workspace` MinIO bucket every 10 minutes, so edits
you make there become S3 events and, through minio-router, run any file
processor whose PATTERN matches.

`workspace/ai/` is excluded. That is the loop break: it is where the agent
automations write, and syncing it would make every answer an event and every
event another run. OpenViking indexes it straight off disk regardless, so past
output stays searchable — it simply cannot trigger anything.

Detection is a poll, so a change takes up to ten minutes to be noticed. Tighten
the schedule if that is too slow; each run is one rclone listing when nothing
changed.

Before activating this, make sure the bucket exists and you have synced once
BEFORE subscribing it to the webhook — otherwise the first pass uploads the whole
workspace and arrives as one event per file. See
migrations.example/03-create-workspace-bucket.md.

Copy to decree/cron/ to activate.
