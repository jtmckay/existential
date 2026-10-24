---
machine: develop
---
# Copy is written for one audience, recorded in .claude/reference/audience.md

## Overview

The site's copy drifted generic because nothing said who it is for. Existential is not for
the majority. Recording the audience once gives every future copy change something to be
checked against.

## Outcome

`.claude/reference/audience.md` exists and contains the sections below, in these exact words.
`CLAUDE.md`'s "Read before you…" table has a row pointing at it for changes to the homepage,
`README.md`'s opening or `site/docs/intro.md`'s opening.

### Who

- **A1.** People with ADHD, or a brain that works like it: hyper-focused, holding a lot of
  context at once, highly motivated, ambitious.
- **A2.** They aren't short on ideas or drive. On a good day they see exactly how things fit
  and get more done than most people do in a week.
- **A3.** They keep falling short of what they know they could be. It isn't laziness. The good
  days don't carry over.

### The pattern they live in

- **A4.** A clear day: the plan, the system, three projects started.
- **A5.** Then a foggy week. The thread is gone. The notes exist, somewhere.
- **A6.** Weeks later they find the note and realize they'd already solved it, or they solve it
  again from scratch without noticing.
- **A7.** Every system they've tried needed them to remember to use it, which is exactly what a
  bad day takes away.
- **A8.** Their attention is easy to hijack, and every app is built to do exactly that.

### What they want

- **A9.** For the clear day to keep working when they're not clear.
- **A10.** To spend good days climbing, not catching up.
- **A39.** What they decided matters, brought back to them. Not a summary of what other people
  decided needs their attention: an email brief is the attention economy with better
  manners. It can summarize email too, but only because they asked it to.
- **A43.** They can't rely on remembering at the moment it matters, so willpower is the wrong
  fix. What works is changing their environment: what they meant to do is already waiting
  where they'll be when it matters. Existential is that environment. The same structure is
  what makes an AI useful to them, because the AI forgets between conversations too, and a
  structured environment lets it fill vague gaps well. Copy says "environment"; the
  implementation's folder stays "workspace".

### What their life looks like

- **A15.** Forty browser tabs, each one a thread they meant to come back to.
- **A16.** Notes in five places: an Obsidian vault, a notes app, voice memos never played back,
  texts to themselves, the back of a receipt.
- **A17.** A folder of side projects, most of them started on the same kind of clear night.
- **A18.** They work in bursts: nothing for days, then twelve hours straight past midnight.
- **A19.** Calendars and to-do lists work for a week and then stop being opened.

### Where they spend time online

Early adopters are in A20 and A21 today, because the current product is easiest for them to
run. The audience as a whole is wider (r/ADHD, ADHD creators, the Obsidian community), and
copy is written for all of it.

- **A20.** r/ADHD, r/selfhosted, r/homelab, r/ObsidianMD, r/productivity.
- **A21.** Hacker News, GitHub, and the Obsidian forum and Discord.
- **A22.** YouTube: homelab builds, desk and "my setup" tours, PKM and Obsidian walkthroughs,
  ADHD creators.
- **A23.** Using Claude or ChatGPT daily, often to think out loud.

### What they've tried

- **A24.** The graveyard: Notion, Todoist, Things, TickTick, bullet journals, GTD, Pomodoro
  timers, Motion or Sunsama, an Obsidian vault with forty plugins, Zapier and IFTTT.
- **A25.** Each one worked while it was new. The novelty wore off in about two weeks, and the
  system went with it.
- **A26.** They have built their own system more than once. Building it was the fun part.
- **A40.** They reject structure someone else designed, often before it has stopped being
  novel, and want to substitute their own. A tool too rigid gets abandoned; a tool too open
  becomes another project. The way through is creativity inside constraints that stay out of
  the way.
- **A41.** So they build their own processes and workflows, and rebuild them when those stop
  fitting. That is not failure; it is how they work. What matters is that rebuilding never
  starts from zero: the last system's decisions are still there, readable, and become raw
  material for the next one.
- **A42.** That is why everything is plain files: markdown, YAML, data structures a person can
  read and any future tool can consume. No proprietary formats, no export button, nothing
  locked inside an app they'll have moved on from.

### What they care about

- **A27.** Being the person they are on their good days, more often.
- **A28.** Owning their tools and their data. They distrust products that profit from their
  attention, because they know they're the easiest mark.
- **A29.** Building things. Making the tool is part of who they are, not a chore.
- **A30.** Not wasting what they're capable of.

### What it feels like

- **A31.** The high of a hyperfocus day, and knowing it won't last.
- **A32.** The quiet shame of the unfinished-projects folder.
- **A33.** Finding a note from three weeks ago that already solved today's problem.
- **A34.** Being told to "just be consistent" by people whose brains don't work like theirs.

### Why they'd try it, and why they'd hesitate

- **A35.** They find it on a clear day, usually right after losing an idea that mattered.
- **A36.** Their first objection is "another system I'll abandon." The answer is that it keeps
  working after they stop paying attention to it, which is the moment every other system
  died.
- **A37.** Their second objection is that setup will become the procrastination. The answer is
  one evening of setup, then it runs, and the tinkering is optional.

### Who it's not for

- **A11.** People whose good days already carry over, who don't need a system to hold them,
  or who are content with what the attention economy hands them.

### Voice

- **A12.** Write to one person, as "you". Describe concrete scenes, not adjectives.
- **A13.** No clinical claims (it doesn't treat anything). No "hack", "unlock" or "supercharge".
- **A14.** The homepage never names ADHD or any diagnosis. The copy describes the experience
  closely enough that the reader recognizes themselves without being labeled. If someone reads
  it and thinks "this is about me", the copy works. If they think "this is for people with
  ADHD", it's too on the nose.

### Today's barrier to entry

This describes the product, not the person, and nothing in the audience depends on it.

- **A38.** Today it takes Docker, a terminal and a spare machine, or an AI to walk you through
  them. That's the gap between a prototype and a product, and it will close. Copy for the
  audience doesn't assume technical skill; installation details belong on Getting Started,
  not in the pitch.

## Constraints

- Only `.claude/reference/audience.md` and the one `CLAUDE.md` row change. No site copy changes.

## Acceptance Criteria

- **Given** `.claude/reference/audience.md`
  **When** it is read
  **Then** it contains A1 through A43 as written above
- **Given** the homepage source (`site/src/pages/index.tsx` and the components it renders)
  **When** it is searched (case-insensitive) for "ADHD"
  **Then** nothing is found
