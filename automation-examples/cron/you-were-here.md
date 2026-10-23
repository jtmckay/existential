---
cron: "0 7 * * *"
machine: you_were_here
---

The morning "you were here" digest: what is waiting on you, what is holding steady,
where you left off, written to workspace/notes/you-were-here.md (and that day's
archive, notes/you-were-here/<YYYY>/<date>.md) and pushed through ntfy when something
changed since the last one.

Active by default: automation's exist.initial.sh copies this into
volumes/workspace_data/.decree/cron/ whenever that copy is missing. Edit the copy to
change the time; to turn it off, set its cron to "0 0 31 2 *" (never). To write one now:

  docker exec automation decree emit --machine you_were_here </dev/null
