---
name: Workspace Agent
tagline: Files you edit in workspace/ are matched against criteria and handed to an agent
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
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
    → workspace-sync bisyncs workspace/ with the workspace/ subfolder of the
      nextcloud MinIO bucket (cron) — the same bucket Nextcloud mounts at /S3
    → MinIO fires an S3 event → POST http://automation-webhook:8801/minio
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

Because the bucket doubles as Nextcloud's own storage, subscribing it to the
webhook (step 5 below) means every Nextcloud file event fires it too — not
just workspace/ ones. `minio-router`'s PATTERN match is what keeps that from
mattering: give your processor a PATTERN scoped to `nextcloud:S3/workspace/`
if you only want it reacting to workspace edits.

The loop break — the one thing worth understanding:
  workspace/ai/ IS indexed into OpenViking, so an agent can find and build on
  what an earlier run produced. It is NOT synced to MinIO, so nothing written
  there ever becomes an event. Without that exclusion, every answer would
  trigger another run, forever.

Setup:

  If you ran the Core quest with MinIO, Nextcloud and Decree enabled, most of
  this already happened for you: the bucket, the workspace-sync cron, the
  nextcloud rclone remote, and minio-router/file-processor enabled — Core
  self-subscribes the bucket to the webhook the first time workspace-sync
  syncs, so there is nothing to do by hand for any of that. What Core does
  NOT set up is the agent half, since it's specific to this quest:

  1. Copy the agent-handoff processor:
       mkdir -p automation/lib/file-processors/
       cp automation/lib/file-processors.example/agent-handoff.sh \
          automation/lib/file-processors/

  2. Enable `agent-task` in services/automation/decree/config.yml
     (`minio-router` and `file-processor` are already on by default). The
     daemon restarts itself when its config changes.

  3. If you did NOT run Core with these services enabled, you need the
     pieces above too — enable the services listed at the top of this quest,
     run `./existential.sh && docker compose up -d`, then copy
     services/automation/backup/cron.example/workspace-sync.md to
     services/automation/backup/cron/ and
     automation-examples/migrations/23-nextcloud-rclone-remote.md to
     automation/migrations/.

  4. Check the agent half works before relying on it:
       docker exec automation opencode run "reply with the word ready"

Then write your own matches. Copy any file in
automation/lib/file-processors.example/ into automation/lib/file-processors/
and edit its PATTERN and CRITERIA — no restart needed, minio-router reads the
directory per event.

CRITERIA is the part worth rewriting. It is the whole judgment, and looking for
the wrong thing is the only way this setup wastes real work. The shipped example
looks for unresolved questions; make it look for whatever you actually want
chased down. Leave CRITERIA empty and the path match is the whole test.

Detection is a poll, not a watch, so a change takes up to ten minutes to be
noticed — MinIO fires events for objects written through its own API, and edits
to the workspace bind mount are not that.

Logs for each run land in automation/runs/ and are queryable in Grafana via the
Decree Overview dashboard.
