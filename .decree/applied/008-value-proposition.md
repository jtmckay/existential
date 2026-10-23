---
machine: develop
---
# The homepage leads with: your best brain day, preserved for your worst

## Overview

The project's pitch was "an active second brain" built from "software that already exists".
Neither is the point. The value is turning an idea you had on a good day into a durable
workflow, so on a rough brain day, or when you simply don't remember, what you already decided
is still there and still running.

## Outcome

- The site tagline (shown in the homepage hero and wherever the site title appears with it) is:
  **Taking your best brain day, and preserving it for your worst.**
- The hero's supporting line says, in one or two sentences, that Existential turns your ideas
  into durable workflows, so when you don't remember or it's a rough brain day, what you
  already decided is still there.
- The homepage's Input / Workspace / Automation section keeps its three items and its meaning.
- Nothing on the homepage pitches "second brain" or "the software already exists". Any
  section built only on those ideas is reframed around the value proposition or removed.
- `README.md`'s opening and `site/docs/intro.md`'s opening make the same pitch as the hero,
  in the same words where they overlap.
- The homepage's meta description matches the new pitch.

## Constraints

- The headline is the exact sentence above.
- No new homepage components; reuse or remove existing ones.

## Acceptance Criteria

- **Given** the docs site build
  **When** it runs
  **Then** it succeeds
- **Given** `site/src/`, `site/docusaurus.config.ts`, `README.md` and `site/docs/intro.md`
  **When** they are searched (case-insensitive) for "second brain" and "software already exists"
  **Then** neither phrase is found
- **Given** the built homepage
  **When** its hero is read
  **Then** it shows the headline sentence exactly
