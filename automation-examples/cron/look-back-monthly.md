---
cron: "0 21 28-31 * *"
machine: look_back
params:
  period: month
  period_end_only: true
---

On the last evening of every month, a look back over the month from the "you were here"
archive, written next to the day notes as notes/you-were-here/<YYYY>/look-back-<first>-<last>.md,
with a short ntfy pointing at it. A year-scale look back reads these, not 365 day notes.

Cron has no "last day of the month", so this fires on the 28th to the 31st and
period_end_only writes only on the one that is the last.

Active by default: automation's exist.initial.sh copies this into
volumes/workspace_data/.decree/cron/ whenever that copy is missing. To turn it off, set
its cron to "0 0 31 2 *" (never).
