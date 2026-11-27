---
machine: repo_develop
---
# "You were here" every morning, and a look back over any range

## Overview

On a foggy day the hard part isn't doing the work. It's remembering where you were, what you
already decided, and what's waiting on you, without spending the next good day catching up.
The digest answers that in one glance. It's the ratchet's floor made visible: it shows what
needs you, and also what is holding steady so you don't need to think about it.

## Outcome

- The `you_were_here` plugin (a default) writes `workspace/ai/you-were-here.md` and pushes the
  digest to ntfy's `digest` topic, every morning at 07:00, and on demand through `POST
  /you-were-here` on automation-webhook or `decree emit` from code-server's terminal.
- The ntfy message carries the digest itself, not just a link: The picture, Waiting on you,
  One next thing, Holding steady, then a link to the note. It stays under ntfy's message
  limit by cutting at section boundaries. The note also has an "Everything else" section:
  recent decisions, notes touched with their open checkboxes, what's scheduled, and what
  changed since the last digest.
- Sections in order:
  - **The picture**: two or three sentences.
  - **Waiting on you**: at most 3. From `.decree/attention/` and runs waiting on a person.
  - **One next thing.**
  - **Holding steady**: machines whose last run succeeded, active schedules.
  - **Where you left off**: threads from captured prompts (`capture.md`) by project,
    and the last prompt of each captured session, which is where you left off.
  - **From your feeds**: present only when `workspace/notes/feeds.md` exists. The 3–5 new
    items most related to what you were working on, each with a one-line reason, never
    repeated across digests, and never one a workspace note already links to (you saw it and
    kept it).
  - **Worth learning**: one Wikipedia article on a subject the person has been looking into.
    The model names the subject as a short phrase; Wikipedia's search finds the article, so
    the link is always a real page and the model never writes one. Never suggested twice,
    never one a note already links to. Only the phrase leaves the machine; the machine's
    `wikipedia` param is the language edition, and blank turns it off. With the model
    unreachable, there is no subject and no section.
  - **Everything else**: note only.
- Every section except The picture, One next thing, the feed reasons and Worth learning's
  subject is built from data,
  with no model involved. The model writes only those parts, works only from the gathered
  facts, and links each claim to its source. With the model unreachable, the digest is
  still written and sent without them.
- Every digest is also archived as that day's note, `workspace/ai/you-were-here/<YYYY>/<YYYY-MM-DD>.md`,
  and archives are never rewritten or deleted afterwards. A day with several digests keeps the
  last. `workspace/ai/you-were-here.md` is always the latest.
- Each archived day has a **Done** section built from data: checkboxes ticked, machines and
  migrations that landed, runs that finished, notes created, and captured threads with their
  project or context. That turns the archive into a record of what you did, not only of
  what was waiting.
- "Recent" means since the last digest that showed something new, so a long gap doesn't
  empty it.
- When nothing changed since the last digest, the note is refreshed but no push is sent.
- Decisions outside decree live in `workspace/notes/decisions/`. Captured prompts that read
  like decisions are listed as candidates for you to confirm, never as decided.

### Look back

"What did I even do this year?" comes up at reviews, at the year's end and on any rough day
that feels like nothing got done. The daily "you were here" archive already holds the record:
what landed, what was finished, what you were working on. A look back turns a range of it into
something you can read in minutes, and filter to work.

- On demand (`POST /look-back` on automation-webhook, or the machine run from the work dir), a
  look back for any date range writes `workspace/ai/you-were-here/<YYYY>/look-back-<from>-<to>.md`
  and sends a short ntfy pointing at it.
  - The default range is the current year to date.
  - Week, month, quarter and year are one parameter each.
- With `./existential.sh plugin on look_back`, every Sunday a weekly look back and every
  month-end a monthly one are written, next to the daily notes. A year-scale look back reads those, not 365 days of raw notes.
- A look back has:
  - **Highlights**: what shipped or finished, grouped by project or context.
  - **Themes**: what you kept coming back to.
  - **Decisions made**: from `notes/decisions/` and landed machines.
  - **By the numbers**: counts only, no judgement.
  Every item links back to the day note it came from.
- **Scope**: everything by default, or `work` only. What counts as work is one editable list
  of projects, folders and capture sources in `workspace/ai/you-were-here/scope.md`.
- Facts come from the archive. The model writes only the grouping and the prose, and each
  claim links to its source. With the model unreachable, the look back is the data sections
  alone.

## Constraints

- No streaks, no "you missed N days", no guilt metrics.
- Models are reached only through the stack's OpenAI-compatible endpoint helper.
- Reuses the existing RSS reader. No second feed parser.
- Builds only on the daily archive from the digest. No second data collector.
- Reads the archive, never rewrites it.

## Acceptance Criteria

- **Given** an attention file and a successful machine run
  **When** the digest runs with the model unreachable
  **Then** the note lists the attention item under Waiting on you and the machine under
  Holding steady, and the ntfy body contains both
- **Given** `workspace/notes/feeds.md` absent
  **When** the digest runs
  **Then** it has no feeds section
- **Given** a feed item shown in one digest
  **When** the next digest runs
  **Then** that item isn't shown again
- **Given** digests on two different days
  **When** both have run
  **Then** both day notes exist under `ai/you-were-here/<YYYY>/` and the first is unchanged
- **Given** no change since the last digest
  **When** it runs
  **Then** no ntfy message is sent
- **Given** archived day notes across three months
  **When** a look back for that quarter runs
  **Then** its file exists, and every Highlights item links to a day note in that range
- **Given** a work scope naming one project
  **When** a `work` look back runs
  **Then** it contains items only from that project
- **Given** a Sunday
  **When** the scheduled run fires
  **Then** that week's look back is written next to the day notes
