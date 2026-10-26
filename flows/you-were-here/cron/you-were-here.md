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
