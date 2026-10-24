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

- **V1. Tagline** (hero subtitle, and the site tagline): Your best brain day now accessible.
- **V2.** Can't remember what you've forgotten? Change your environment to remember for you.
- **V3.** Existential is that environment. It's just a notepad, until you tell it what to do.
- **V4.** Every system you've tried needed you to remember to use it. That's the first thing a
  bad day takes.
- **V5.** Everything else on your phone surfaces what someone else decided needs your
  attention. This surfaces what you decided.
- **V6.** What you're building is your Diagram: the plan from your best day, followed on the
  rest.

V2 and V3 are the hero lede. The first section after the hero is headed **Intentional
attention** and holds V4 through V6.

"Environment" is the pitch's word for what Existential sets up around you. The implementation
keeps calling the folder the workspace.

Everything else that pitches the project says the same thing, in the voice
`.claude/reference/audience.md` sets:

- The rest of the homepage, `README.md`'s opening, `site/docs/intro.md`'s opening and the site's
  meta description carry this proposition. Where they repeat V1 to V6 they use the same words.
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
  **When** its hero and first section are read
  **Then** they show V1 through V6 exactly, and the heading "Intentional attention"
- **Given** `site/src/`, `site/docusaurus.config.ts`, `README.md` and `site/docs/intro.md`
  **When** they are searched (case-insensitive) for "second brain", "software already exists",
  "nothing leaves the house" and "unplug the internet"
  **Then** none is found
- **Given** `site/`, `README.md` and `.claude/`
  **When** they are searched (case-insensitive) for "Taravangian", "Sanderson" and "Stormlight"
  **Then** none is found
