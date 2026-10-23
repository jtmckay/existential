---
machine: develop
---
# Look back: what did I do this year?

## Overview

"What did I even do this year?" comes up at reviews, at the year's end and on any rough day
that feels like nothing got done. The daily "you were here" archive already holds the record:
what landed, what was finished, what you were working on. A look back turns a range of it into
something you can read in minutes, and filter to work.

## Outcome

- On demand (`POST /look-back` on automation-webhook, or the machine run from the work dir), a
  look back for any date range writes `workspace/notes/you-were-here/<YYYY>/look-back-<from>-<to>.md`
  and sends a short ntfy pointing at it.
  - The default range is the current year to date.
  - Week, month, quarter and year are one parameter each.
- Every Sunday a weekly look back and every month-end a monthly one are written automatically,
  next to the daily notes. A year-scale look back reads those, not 365 days of raw notes.
- A look back has:
  - **Highlights**: what shipped or finished, grouped by project or context.
  - **Themes**: what you kept coming back to.
  - **Decisions made**: from `notes/decisions/` and landed machines.
  - **By the numbers**: counts only, no judgement.
  Every item links back to the day note it came from.
- **Scope**: everything by default, or `work` only. What counts as work is one editable list
  of projects, folders and capture sources in `workspace/notes/you-were-here/scope.md`.
- Facts come from the archive. The model writes only the grouping and the prose, and each
  claim links to its source. With the model unreachable, the look back is the data sections
  alone.

## Constraints

- Builds only on the daily archive from `011-you-were-here.md`. No second data collector.
- Reads the archive, never rewrites it.

## Acceptance Criteria

- **Given** archived day notes across three months
  **When** a look back for that quarter runs
  **Then** its file exists, and every Highlights item links to a day note in that range
- **Given** a work scope naming one project
  **When** a `work` look back runs
  **Then** it contains items only from that project
- **Given** a Sunday
  **When** the scheduled run fires
  **Then** that week's look back is written next to the day notes
