---
machine: plugin
automation: you-were-here
name: You were here
tagline: Every morning, yesterday in one notification, then it ends
docs: /docs/getting-started#you-were-here
services:
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_SERVICES_NTFY
needs:
  - you_were_here
cron:
  you-were-here: |
    ---
    cron: "0 7 * * *"
    machine: you_were_here
    ---

    The morning "you were here" digest: what is waiting on you, what is holding steady,
    where you left off, written to workspace/ai/you-were-here.md (and that day's
    archive, ai/you-were-here/<YYYY>/<date>.md) and pushed through ntfy when something
    changed since the last one.

    On by default (a default flow). Edit the active copy in
    volumes/workspace_data/.decree/cron/ to change the time; `./existential.sh flow off
    you-were-here` turns it off. To write one now:

      docker exec automation decree emit --machine you_were_here </dev/null
---

Runs at 07:00 with a chat model (EXIST_MODEL_URL); with none it still writes the
parts built from files. The digest is ai/you-were-here.md in the workspace.
