---
machine: develop
---
# The homepage pitches the Diagram: your best day's decisions, run on every other day

## Overview

The pitch has to mean something to a stranger in one read. Generic lines ("build systems that
work for you", "less screen time, more headspace", "take ownership of your digital life")
could sit on any product's page and say nothing. Existential is one specific thing.

In Brandon Sanderson's *The Stormlight Archive*, Taravangian wakes every morning with a
different mind. Some days he can barely follow a conversation. One day he was a genius, and
in that single day he wrote the Diagram, which he has followed ever since, on days he could
not have understood a page of it. That is what Existential builds: your Diagram. The sharp
days write it, as decree machines, and every other day runs it.

The second idea is the attention economy. Every notification on a phone has an author, and
it is almost never the person holding the phone. Here, nothing reaches you that you did not
put there yourself.

The page takes a side and names the idea. That is the risk, and it is deliberate.

## Outcome

The homepage, README opening and intro opening read as below. Where a block is quoted, the
words are exact: the copy is the spec. The agent changes structure and markup only as far as
needed to show it.

- **Site tagline** (hero subtitle, and wherever the site title appears with it), unchanged:
  **Taking your best brain day, and preserving it for your worst.**
- **Hero lede:**
  > Some mornings you wake up able to see the whole board. Most mornings you don't.
  > Existential is where the sharp you leaves orders for every other you, and makes sure
  > they're carried out.
- **First section after the hero**, heading **Write your Diagram.**
  > In Brandon Sanderson's *Stormlight Archive*, Taravangian wakes every day with a different
  > mind. Most days he's ordinary. Some days he can barely follow a conversation. One day he
  > was a genius, and in that one day he wrote the Diagram. He has followed it ever since, on
  > days he couldn't have written a line of it.
  >
  > That's what you're building here. Not a notes app, not a dashboard: a Diagram. What you
  > decide on your best days is written down as a [decree machine](/docs/decree), and it runs
  > on the days you've forgotten why.
  >
  > So the good days stop being spent catching up. Each one starts where the last one left
  > you, and climbs.
- **Second section**, heading **Nobody else decides what you look at.**
  > Every app on your phone is bidding for your next thirty seconds, and the winner is
  > whoever profits most from them. Here, nothing reaches you unless you put it there: the
  > reminder you set on a sharp day, the feeds you chose, this morning's
  > ["you were here"](/docs/getting-started#you-were-here) digest of what you were in the
  > middle of. Everything you put in lands in one [capture](/docs/getting-started#capture)
  > stream; everything that comes back arrives through [ntfy](/docs/services/ntfy), when you
  > said it should.
  >
  > Every interruption has an author. Here, it's you.
- **Who this is for**, lede **If three of these sting, it's for you.**, items:
  - You've had the same good idea three times and lost it twice.
  - Your best plans don't survive your first bad week.
  - You want your phone to interrupt you for your reasons, not someone else's.
  - You'd rather write a rule once than remember it forever.
  - You'd rather own a box in the closet than rent your own life back monthly.
  - You want to answer "what did I even do this year?" with something better than a guess.
- **What gets easier**, heading **What the Diagram does on a bad day**, lede
  **The days you'd have dropped it.**, cards (label: text):
  - Remembers: What you were in the middle of is in this morning's notification, word for word.
  - Keeps promises: The thing you swore you'd check every Friday gets checked every Friday.
  - Captures: Every prompt you give an agent lands in one stream, searchable a year from now.
  - Looks back: "What did I even do this year?" has an answer.
  - Holds the line: A bad week doesn't undo a good one.
  - Grows: Tell an AI in your work dir what you want automated; it writes the machine.
- **How it works** keeps its three items (Input / Workspace / Automation) and their meaning;
  its lede becomes **Things go in. You decide what comes back out.**
- **How we do it** becomes heading **Why it holds**, lede
  **A decision is a file, not a memory.**, items (title: text):
  - Written down, not remembered: A decision is a file. It runs whether or not you remember making it.
  - Solved once: Hostnames, HTTPS, backups, logs: figured out a single time, for every service after.
  - Yours, physically: It runs on hardware you own. No account to lose, no subscription required,
    nobody who can lock you out.
- **Closing section** heading **Start your Diagram tonight.** Its lede ("One evening, mostly
  spent waiting on Docker.") and the code block stay.
- **Meta description:** Taking your best brain day, and preserving it for your worst. Your
  sharpest decisions, written down as automations that run on every other day, on hardware you
  own. Nothing gets your attention unless you put it there.
- `README.md`'s opening and `site/docs/intro.md`'s opening carry the tagline and the hero
  lede word for word, then one short paragraph that names the Diagram (Taravangian, one line)
  and the attention point (one line). Their "three things it gets you" lists use the **Why it
  holds** titles and text.
- Any claim the copy makes that the repo doesn't back is a defect: "nothing leaves the house"
  and "unplug the internet and it keeps working" go wherever they appear in these files,
  because Claude Code and a remote Nextcloud are part of the default setup.

## Constraints

- The tagline is the exact sentence above.
- No new homepage components; reuse, rename or remove existing ones.
- The links in the quoted copy point at pages that exist (the site build fails on broken links).
- No self-help phrasing ("reach your full potential", "unlock", "supercharge", "second brain",
  "the software already exists").

## Acceptance Criteria

- **Given** the docs site build
  **When** it runs
  **Then** it succeeds
- **Given** the built homepage
  **When** it is read
  **Then** it shows the tagline, the hero lede, and the headings "Write your Diagram." and
  "Nobody else decides what you look at." exactly
- **Given** `site/src/`, `site/docusaurus.config.ts`, `README.md` and `site/docs/intro.md`
  **When** they are searched (case-insensitive) for "second brain", "software already exists",
  "nothing leaves the house", "unplug the internet", "take ownership of your digital life" and
  "less screen time"
  **Then** none is found
- **Given** `README.md` and `site/docs/intro.md`
  **When** they are read
  **Then** each names Taravangian and the Diagram in its opening
