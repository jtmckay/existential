---
machine: plugin
automation: look-back
name: Look back
tagline: A week and a month in review, next to your notes, for when someone asks what you did
docs: /docs/getting-started#look-back
needs:
  - look_back
  - you-were-here
cron:
  look-back-monthly: |
    ---
    cron: "0 21 28-31 * *"
    machine: look_back
    params:
      period: month
      period_end_only: true
    ---

    On the last evening of every month, a look back over the month from the "you were here"
    archive, written next to the day notes as ai/you-were-here/<YYYY>/look-back-<first>-<last>.md,
    with a short ntfy pointing at it. A year-scale look back reads these, not 365 day notes.

    Cron has no "last day of the month", so this fires on the 28th to the 31st and
    period_end_only writes only on the one that is the last.

    On by default (a default flow); `./existential.sh flow off look-back` turns it off.
  look-back-weekly: |
    ---
    cron: "0 21 * * SUN"
    machine: look_back
    params:
      period: week
    ---

    Every Sunday evening, a look back over the week (Monday to today) from the "you were
    here" archive, written next to the day notes as
    ai/you-were-here/<YYYY>/look-back-<monday>-<sunday>.md, with a short ntfy pointing at it.
    A longer look back reads these instead of seven day notes.

    On by default (a default flow); `./existential.sh flow off look-back` turns it off.
---

Sunday evenings for the week, the last evening of each month for the month. For a
year, ask: echo | docker exec -i automation decree emit --machine look_back --param period=year
