---
machine: develop
---
# The homepage leads with: your best brain day, preserved for your worst

## Overview

The project's pitch was "an active second brain" built from "software that already exists".
Neither is the point. The value is turning an idea you had on a good day into a durable
workflow, so on a rough brain day, or when you simply don't remember, what you already decided
is still there and still running.

It works like a ratchet. Your best day sets the floor, a bad day stays on it, and the next good
day climbs from there instead of being spent catching back up. It also answers the attention
economy: what reaches you is what you decided should, not what someone else's algorithm is
paid to put in front of you.

## Outcome

- The site tagline (shown in the homepage hero and wherever the site title appears with it) is:
  **Taking your best brain day, and preserving it for your worst.**
- The hero's supporting line says, in one or two sentences, that Existential turns your ideas
  into durable workflows, so when you don't remember or it's a rough brain day, what you
  already decided is still there.
- Right after the hero, the homepage says two things in a few short beats:
  - **The ratchet.** Without it you get a churn loop: a good day, a bad day, a good day spent
    catching up, then repeat. With it, your best day sets the floor and the next good day climbs
    from there.
  - **Your attention is yours.** What reaches you is what you decided should, on your schedule.
    No algorithm picks it for someone else's profit.
  Each beat is paired with what does it: recorded decisions (decree machines), things brought
  back to you (the "you were here" digest, ntfy), and capture.
- Down days are never the only framing. Every mention of the floor is paired with the climb.
- No "reach your full potential" or similar self-help phrasing.
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
