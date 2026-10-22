---
name: Workspace Agent
tagline: Files you edit in the workspace are matched against criteria and handed to an agent
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
  - var: EXIST_IS_AI_HERMES
    label: Hermes
  - var: EXIST_IS_AI_OPENVIKING
    label: OpenViking
  - var: EXIST_IS_AI_FIRECRAWL
    label: Firecrawl
done:
  files:
    - automation/lib/file-processors/agent-handoff.sh
---

Edit a file in the workspace and, if it matches one of your criteria, an agent
goes and does the work — searching your own knowledgebase and the web — then
files the answer back in `workspace/ai/`.

The pipeline:
  You save workspace/notes/plan.md in the Nextcloud desktop client
    → the upload fires a Nextcloud file event → POST http://automation-webhook:8801/files
    → file-router matches PATTERN against the rclone path      (free)
    → file-processor downloads it, then puts CRITERIA to hermes  (one call)
    → agent-handoff.sh queues agent-task for what passed both
    → agent-task calls the hermes gateway, which reaches
      OpenViking and Firecrawl through its own MCP servers
    → the answer lands in workspace/ai/plan-followup.md

Why the workspace is the knowledgebase: it is the same tree Nextcloud serves as
its `workspace` folder, hermes mounts at /opt/data/workspace and code-server
mounts at /workspace. OpenViking indexes it every 15 minutes, so everything you
work on is searchable without a second directory to keep in step.

Every Nextcloud upload fires the webhook, not just workspace ones. file-router's
PATTERN match is what keeps that from mattering: the shipped processor is scoped
to `^nextcloud:workspace/`.

The loop break — the one thing worth understanding:
  Only uploads THROUGH Nextcloud fire events. The agent writes workspace/ai/
  straight to disk, so its answer is indexed and shows up on your desktop, but
  can never trigger another run. The same goes for edits in code-server's
  editor: they sync to your devices, but do not fire.

Setup:

  If you ran the Core quest, the Nextcloud half already happened: the rclone
  remote and the file-event webhooks. What
  Core does NOT set up is the agent half, since it's specific to this quest:

  1. Copy the agent-handoff processor:
       mkdir -p automation/lib/file-processors/
       cp automation/lib/file-processors.example/agent-handoff.sh \
          automation/lib/file-processors/

  2. If you did NOT run Core, you need the Nextcloud half too — enable the
     services listed at the top of this quest, run
     `./existential.sh && docker compose up -d`, then copy
     automation-examples/migrations/23-nextcloud-rclone-remote.md and
     27-nextcloud-file-events.md to automation/migrations/.

  3. Check the agent half works before relying on it — the gateway answers
     the automation container:
       docker exec automation sh -c 'curl -sf \
         -H "Authorization: Bearer $HERMES_API_KEY" \
         http://hermes-agent:8642/v1/models'

Then write your own matches. Copy any file in
automation/lib/file-processors.example/ into automation/lib/file-processors/
and edit its PATTERN and CRITERIA — no restart needed, file-router reads the
directory per event.

CRITERIA is the part worth rewriting. It is the whole judgment, and looking for
the wrong thing is the only way this setup wastes real work. The shipped example
looks for unresolved questions; make it look for whatever you actually want
chased down. Leave CRITERIA empty and the path match is the whole test.

Logs for each run land in automation/runs/ and are queryable in Grafana via the
Decree Overview dashboard.
