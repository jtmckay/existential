---
machine: develop
---
# The homepage leads with the value proposition

## Overview

The pitch is written for the audience in `.claude/reference/audience.md` (migration 014): people
whose clear days don't carry over, and who are tired of every system that needed them to
remember to use it. It has to land in one read, in plain words.

What they build here is their Diagram: the plan their best day wrote, followed on every other
day. The word is a quiet nod for readers who know where it comes from, and a plain word for
everyone else. Nothing names its source.

## Outcome

The homepage hero and the first section after it read as below, in these exact words.

- **V1. Tagline** (hero subtitle, and the site tagline): Your best brain day now carries your
  worst.
- **V2.** On a clear day you can see exactly what to do. Then the fog rolls in, and the idea
  sits in a note you won't open for three weeks.
- **V3.** Existential keeps the clear day running. What you decide when you're sharp becomes an
  automation that comes to you on its own, on the days you'd never think to look.
- **V4.** Every system you've tried needed you to remember to use it. That's the one thing a
  bad day takes.
- **V5.** Your good days stop going to catching up. Each one starts where the last one left
  off.
- **V6.** Everything else on your phone surfaces what someone else decided needs your
  attention. This surfaces what you decided.
- **V7.** What you're building is your Diagram: the plan your best day wrote, followed on every
  other one.

- **V8.** When you outgrow how you set it up, and you will, rebuild it your way. Nothing you
  built is lost: it's all plain files, and it's where the next version starts.
- **V9.** Existential makes no money from you: no ads, no attention to sell, nothing collected.
  Which AI you talk to is your choice, as private or as easy as you want. Your data improves
  you.

V2 and V3 are the hero lede. V4 through V7 are the first section after the hero. V8 and V9
are the second.

Everything else that pitches the project says the same thing, in the voice
`.claude/reference/audience.md` sets:

- The rest of the homepage, `README.md`'s opening, `site/docs/intro.md`'s opening and the site's
  meta description carry this proposition. Where they repeat V1 to V9 they use the same words.
- No copy assumes the reader is technical. How to install belongs on Getting Started, not in
  the pitch.
- No copy pitches something else ("second brain", "the software already exists", "nothing
  leaves the house", "unplug the internet"), and no copy claims what the repo doesn't back.

## Constraints

- No new homepage components.
- No author, book, series or character is named. "Diagram" is the only nod.

## Acceptance Criteria

- **Given** the docs site build
  **When** it runs
  **Then** it succeeds
- **Given** the built homepage
  **When** its hero and first two sections are read
  **Then** they show V1 through V9 exactly
- **Given** `site/src/`, `site/docusaurus.config.ts`, `README.md` and `site/docs/intro.md`
  **When** they are searched (case-insensitive) for "second brain", "software already exists",
  "nothing leaves the house" and "unplug the internet"
  **Then** none is found
- **Given** `site/`, `README.md` and `.claude/`
  **When** they are searched (case-insensitive) for "Taravangian", "Sanderson" and "Stormlight"
  **Then** none is found
