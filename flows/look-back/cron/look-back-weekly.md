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

On by default (a default flow); `./existential.sh flow off look-back` turns it off.
