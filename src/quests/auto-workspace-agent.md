---
name: Workspace Agent
tagline: Files you edit in workspace/ are matched against criteria and handed to an agent
e2e: false
services:
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree
  - var: EXIST_IS_NAS_MINIO
    label: MinIO
  - var: EXIST_IS_AI_HERMES
    label: Hermes
  - var: EXIST_IS_AI_OPENVIKING
    label: OpenViking
  - var: EXIST_IS_AI_FIRECRAWL
    label: Firecrawl
---

Edit a file in `workspace/` and, if it matches one of your criteria, an agent
goes and does the work — searching your own knowledgebase and the web — then
files the answer back in `workspace/ai/`.

The pipeline:
  You edit workspace/notes/plan.md
    → workspace-sync mirrors workspace/ into the minio:workspace bucket (cron)
    → MinIO fires an S3 event → POST http://decree-webhook:8801/minio
    → minio-router matches PATTERN against the rclone path      (free)
    → file-processor downloads it, then puts CRITERIA to hermes  (one call)
    → agent-handoff.sh queues agent-task for what passed both
    → agent-task runs `opencode run` against hermes, which reaches
      OpenViking and Firecrawl through its own MCP servers
    → the answer lands in workspace/ai/plan-followup.md

Why workspace/ is the knowledgebase: it is the same tree hermes mounts at
/opt/data/workspace and code-server mounts at /workspace. OpenViking indexes it
every 15 minutes, so everything you work on is searchable without a second
directory to keep in step.

The loop break — the one thing worth understanding:
  workspace/ai/ IS indexed into OpenViking, so an agent can find and build on
  what an earlier run produced. It is NOT synced to MinIO, so nothing written
  there ever becomes an event. Without that exclusion, every answer would
  trigger another run, forever.

Setup:

  1. Copy the templates this needs — the workspace-bucket migration and the
     mirror cron (both MinIO-side), and the agent-handoff processor:
       mkdir -p services/decree/decree/migrations/ services/decree/decree-backup/cron/ \
                automations/lib/file-processors/
       cp services/decree/decree/migrations.example/22-minio-create-workspace-bucket.md \
          services/decree/decree/migrations/
       cp services/decree/decree-backup/cron.example/workspace-sync.md \
          services/decree/decree-backup/cron/
       cp automations/lib/file-processors.example/agent-handoff.sh \
          automations/lib/file-processors/

  2. Enable the services above and run:
       ./existential.sh
       docker compose up -d

  3. Enable the routines. In services/decree/decree/config.yml set
     `minio-router`, `file-processor` and `agent-task` to enabled: true.
     `workspace-sync` is already on in services/decree/decree-backup/config.yml.
     Both daemons restart themselves when their config changes.

  4. The bucket is created by the migration you copied in step 1, on the
     `docker compose up -d` you just ran. Confirm it exists:
       docker exec decree-backup rclone lsd minio:

  5. Sync ONCE, before subscribing. The first pass uploads the whole workspace;
     against a subscribed bucket that arrives as one event per file. Drop a
     message in the backup daemon's inbox and wait for it to finish:
       printf -- '---\nroutine: workspace-sync\n---\n' \
         > services/decree/decree-backup/inbox/sync-once.md
       docker logs -f decree-backup

  6. NOW subscribe the bucket to the webhook:
       docker exec minio mc event add minio/workspace \
         arn:minio:sqs::DECREE:webhook --event put,delete

  7. Check the agent half works before relying on it:
       docker exec decree opencode run "reply with the word ready"

Then write your own matches. Copy any file in
automations/lib/file-processors.example/ into automations/lib/file-processors/
and edit its PATTERN and CRITERIA — no restart needed, minio-router reads the
directory per event.

CRITERIA is the part worth rewriting. It is the whole judgment, and looking for
the wrong thing is the only way this setup wastes real work. The shipped example
looks for unresolved questions; make it look for whatever you actually want
chased down. Leave CRITERIA empty and the path match is the whole test.

Detection is a poll, not a watch, so a change takes up to ten minutes to be
noticed — MinIO fires events for objects written through its own API, and edits
to the workspace bind mount are not that.

Logs for each run land in automations/runs/ and are queryable in Grafana via the
Decree Overview dashboard.
