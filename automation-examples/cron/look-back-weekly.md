---
cron: "0 21 * * SUN"
machine: look_back
params:
  period: week
---

Every Sunday evening, a look back over the week (Monday to today) from the "you were
here" archive, written next to the day notes as
notes/you-were-here/<YYYY>/look-back-<monday>-<sunday>.md, with a short ntfy pointing at it.
A longer look back reads these instead of seven day notes.

Active by default: automation's exist.initial.sh copies this into
volumes/workspace_data/.decree/cron/ whenever that copy is missing. To turn it off, set
its cron to "0 0 31 2 *" (never).
