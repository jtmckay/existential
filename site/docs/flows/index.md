---
sidebar_position: 1
---

# Flows

:::info[Level 3 of 4 · Components]
One job traced through the services it touches. Back out to [Level 2 · The Pieces](../how-it-works),
or go on to [Level 4 · Build On It](../build-on-it) to write your own.
:::

A flow is one complete path from *something happened* to *it was handled*.

That's the level Existential is meant to be understood at. Underneath, a flow might touch
half a dozen services — but you set it up once and then think about it as a single thing:
**a recording becomes a transcript**, **a receipt becomes a budget entry**, **a file becomes
a filed file**.

## How every flow works

All of them have the same four parts. Once you've seen one, you've seen all of them.

```
  input  →  judgment  →  work  →  output
```

1. **Input.** A file appears, an email arrives, you talk to your phone, a service fires a
   webhook, a schedule comes around. Everything ends up as a message in one queue.
2. **Judgment.** One cheap question: *is this worth doing anything about?* Most things are
   not — most notes are a grocery list, most files are not receipts. This step is what keeps
   the next one from running on everything.
3. **Work.** The expensive part, and only for what got past judgment. Transcribe, research,
   extract, draft, file. Often several steps, each its own message.
4. **Output.** A note, a task, a budget line, a notification — or another message, which
   starts the next flow.

There is only one queue and one kind of message, so there is only one thing to learn.

:::tip[The judgment step is the one people skip]
It is tempting to wire input straight to work. Don't. A flow with no judgment step runs the
expensive half on everything that arrives, and what you get is a folder of unread reports —
which is the problem you started with. Being stingy here is what makes a flow worth having.
:::

## The four knobs

Those four parts are also the four things you change, and **three of them are settings, not
code.** This is the whole customization model:

| Knob | What it is | How you change it |
|---|---|---|
| **Input** | What triggers the flow | Pick a trigger: a cron file, a webhook endpoint, a file-processor `PATTERN`, an inbox drop |
| **Judgment** | What counts as worth acting on | One line of prompt in cron frontmatter — e.g. `TRIAGE_CRITERIA` |
| **Work** | What actually gets done | The name of the routine to chain — e.g. `TRIAGE_ROUTINE` |
| **Output** | Where the result lands | A destination setting, or the routine you chained |

Turning one knob does not disturb the others. Swap a notes vault for an email inbox and the
judgment and work are untouched; swap "a business idea" for "a house project" and nothing else
moves. [Note → Action](./note-to-action) turns all four on one flow, one section each.

Adding a genuinely new flow means writing one more routine, not learning a new system —
see [Writing a Routine](../writing-a-routine).

## The three that matter most

### Capture → one place

Anything you throw at it gets picked up, understood, and filed — without you choosing a
destination each time.

- [Camera → OCR](./image-ocr) — photograph something, get back its text
- [Note → Action](./note-to-action) — a thought worth chasing gets chased, and comes back with the right questions

### Voice → action

Say it out loud and have it turn into something real, without opening an app.

- [Recording → Transcription](./recording-transcription) — recordings become searchable, speaker-labelled text
- [AutoVoice — Voice Triggers](./autovoice) — speak a phrase, trigger a routine
- [HAwake — Custom Wake Word](./hawake) — train your own wake word
- [HAwake → Home Assistant → Tasker](./hawake-homeassistant) — wake word to phone action, end to end

### Money → budget

The most tedious recurring paperwork in most people's lives, handled without attention.

- [Bank Alert → Gmail → Budget](./transaction-gmail-actual-budget) — transaction emails become budget entries
- [Bank Alert → Receipt Split](./receipt-split) — one charge, split into its real line items

## Building your own

Every flow above is a routine plus a trigger — and both are yours to write.

- **[Writing a Routine](../writing-a-routine)** is the place to start: the anatomy of a
  routine script, how to register it, the four ways to trigger it, and how one routine hands
  work to the next.
- **[Note → Action](./note-to-action)** is the same material as a worked example — four
  routines wired into one flow, with sections on swapping the judgment, the work, and the input.
- **[Build On It](../build-on-it)** is the contract for reaching the stack from *outside* it:
  how to send something in over HTTP and how to read the result.

The mechanism underneath most of them — a file landing in storage becoming a running routine —
is the [File Processor](../decree/file-change-processing). That is a level-4 page: it explains
the plumbing rather than what the system does with it.
