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

## Turning one on

The stack ships its flows ready to switch on, each a folder in `flows/`: the services it needs,
the machine's trigger, and what is left that only you can do.

```bash
./existential.sh flow                 # pick from the list; ✓ marks the ones on
./existential.sh flow on newsletter   # its services on, its machine on, then a rebuild
./existential.sh flow off newsletter  # its machine off; services stay as they are
```

`docker compose up -d` afterwards starts anything new. A flow that needs another turns that one on
too. A file you changed is never deleted by `off`.

| Flow | What it does | Needs, beyond Core |
|---|---|---|
| `you-were-here` | Every morning, yesterday in one notification. **On by default** | a chat model |
| `look-back` | The week and the month in review, next to your notes. **On by default** | a chat model |
| `clean-runs` | Prunes decree's finished run logs after a week. **On by default** | — |
| `health-checks` | Probes a service every 15 minutes, and tells your phone when it stops. **On by default** | — |
| `newsletter` | [Your own newsletter](./newsletter) from only the feeds you picked | a chat model |
| `check-versions` | Mondays, the services with a newer image | — |
| `search` | Your notes, PDFs and Word files, by meaning and by words ([qmd](../ai/qmd)) | qmd |
| `gmail` | New mail every 15 minutes, as decree messages ([Gmail](../integrations/gmail)) | a Google grant |
| `budget` | [Bank alerts become budget entries](./transaction-gmail-actual-budget) | Actual Budget, `gmail` |
| `note-triage` | [The note you meant to come back to](./note-to-action) | Nextcloud, a chat model |
| `knowledgebase` | The workspace indexed into OpenViking for Hermes | OpenViking |
| `note-connect` | [Notes that find their own connections](./note-connect) | Hermes, `knowledgebase` |
| `hermes-knows-decree` | Hourly, what decree can run, written where Hermes reads | Hermes |
| `nextcloud-capture` | A file uploaded through Nextcloud runs the [file processors](../decree/file-change-processing) | Nextcloud, automation-webhook |
| `image-ocr` | [A photo's text, written beside it](./image-ocr) | `nextcloud-capture`, a vision model |
| `transcription` | [Recordings become speaker-labelled transcripts](./recording-transcription) | WhisperX, `nextcloud-capture` |
| `workspace-agent` | A file matching your criteria is handed to an agent | Hermes, OpenViking, Firecrawl, `nextcloud-capture` |
| `notes-to-dropbox` | Nextcloud notes compiled and pushed to Dropbox | `nextcloud-capture`, a Dropbox remote |
| `calendar` | Nextcloud's calendar, every event mirrored into the workspace | Nextcloud |
| `office-documents` | Word, Excel and PowerPoint in the browser | Nextcloud, Collabora |
| `local-models` | Ollama on this machine pulls your tier's models, once | Ollama |
| `home-voice` | Talk to the house: Home Assistant, speech in and out, Hermes answering | Home Assistant, Wyoming, Hermes |
| `comfy` | ComfyUI workflows a decree message runs | ComfyUI and its models |

[Note → Automation](./note-to-automation) needs no flow: it is part of Core, on whenever a chat
model answers.

### Housekeeping

`clean-runs` keeps `workspace/.decree/runs/` from growing forever (run logs go to Loki too, when
it is on). `health-checks` probes ntfy; to probe another service, copy its cron in
`workspace/.decree/cron/` to `health-check-<slug>.md` and set `SERVICE_NAME` and `SERVICE_URL`
(`http://<container>:<port>/<health path>`). `check-versions` tells you when an image is
behind; `./existential.sh run check-versions --update` patches the templates, then
`./existential.sh && docker compose pull && docker compose up -d`. `hermes-knows-decree`
writes `workspace/ai/decree/` every hour, so Hermes, which cannot see `.decree/`, knows what it
may ask decree to run.

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
see [Writing an Automation](../writing-a-routine).

## The three that matter most

### Capture → one place

Anything you throw at it gets picked up, understood, and filed — without you choosing a
destination each time.

- [Camera → OCR](./image-ocr) — photograph something, get back its text
- [Note → Automation](./note-to-automation) — write "next time I…, do…" and it offers to automate exactly that
- [Your Own Newsletter](./newsletter) — a weekly issue from only the feeds you picked, judged by a paragraph you wrote
- [Note → Action](./note-to-action) — a thought worth chasing gets chased, and comes back with the right questions
- [Note → Connection](./note-connect) — a new note gets checked against everything you already know, and the interesting links come back to you unasked

### Voice → action

Say it out loud and have it turn into something real, without opening an app.

- [Recording → Transcription](./recording-transcription) — recordings become searchable, speaker-labelled text
- [AutoVoice — Voice Triggers](./autovoice) — speak a phrase, trigger a routine
- [HAwake — Custom Wake Word](./hawake) — train your own wake word
- [HAwake → Home Assistant → Tasker](./hawake-homeassistant) — wake word to phone action, end to end

### Money → budget

The most tedious recurring paperwork in most people's lives, handled without attention.

- [Bank Alert → Gmail → Budget](./transaction-gmail-actual-budget) — transaction emails become budget entries

## Building your own

Every flow above is a routine plus a trigger — and both are yours to write.

- **[Writing an Automation](../writing-a-routine)** is the place to start: the anatomy of a
  routine script, how to register it, the four ways to trigger it, and how one routine hands
  work to the next.
- **[Note → Action](./note-to-action)** is the same material as a worked example — four
  routines wired into one flow, with sections on swapping the judgment, the work, and the input.
- **[Build On It](../build-on-it)** is the contract for reaching the stack from *outside* it:
  how to send something in over HTTP and how to read the result.

The mechanism underneath most of them — a file landing in storage becoming a running routine —
is the [File Processor](../decree/file-change-processing). That is a level-4 page: it explains
the plumbing rather than what the system does with it.
