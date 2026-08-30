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
copies:
  - src: automations/lib/file-processors.example/agent-handoff.sh
    dst: automations/lib/file-processors/
    label: "file-processors: agent-handoff.sh (flag unresolved notes and hand them to an agent)"
    requires: EXIST_IS_SERVICES_DECREE
  - src: nas/minio/decree/migrations.example/03-create-workspace-bucket.md
    dst: nas/minio/decree/migrations/
    label: "migration: create the workspace bucket"
    requires: EXIST_IS_NAS_MINIO
  - src: nas/minio/decree/cron.example/workspace-sync.md
    dst: nas/minio/decree/cron/
    label: "cron: mirror workspace/ into MinIO every 10 minutes"
    requires: EXIST_IS_NAS_MINIO
---

Edit a file in `workspace/` and, if it matches one of your criteria, an agent
goes and does the work — searching your own knowledgebase and the web — then
files the answer back in `workspace/ai/`.

The pipeline:
  You edit workspace/notes/plan.md
    → workspace-sync mirrors workspace/ into the minio:workspace bucket (cron)
    → MinIO fires an S3 event → POST http://decree-webhook:48880/minio
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

  1. Enable the services above and run:
       ./existential.sh
       docker compose up -d

  2. Enable the routines. In services/decree/decree/config.yml set
     `minio-router`, `file-processor` and `agent-task` to enabled: true.
     In nas/minio/decree/config.yml set `workspace-sync` to enabled: true.
     Both daemons restart themselves when their config changes.

  3. The bucket is created by the migration above on the next
     `docker compose up -d`. Confirm it exists:
       docker exec minio-decree rclone lsd minio:

  4. Sync ONCE, before subscribing. The first pass uploads the whole workspace;
     against a subscribed bucket that arrives as one event per file. Drop a
     message in the MinIO daemon's inbox and wait for it to finish:
       printf -- '---\nroutine: workspace-sync\n---\n' \
         > nas/minio/decree/inbox/sync-once.md
       docker logs -f minio-decree

  5. NOW subscribe the bucket to the webhook:
       docker exec minio mc event add minio/workspace \
         arn:minio:sqs::DECREE:webhook --event put,delete

  6. Check the agent half works before relying on it:
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
