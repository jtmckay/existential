---
sidebar_position: 1
---

# Flows

:::info[Level 3 of 4 · Components]
One job traced through the services it touches. Back out to [Level 2 · The Pieces](../how-it-works),
or go on to [Level 4 · Build On It](../build-on-it) to write your own.
:::

A flow is one job, from *something happened* to *it was handled*: a recording becomes a
transcript, a receipt becomes a budget entry.

## Turning one on

Each flow is a folder in `flows/`: the services it needs, its trigger, and any step only you can do.

```bash
./existential.sh flow                 # pick from the list; ✓ marks the ones on
./existential.sh flow on newsletter   # its services on, its machine on, then a rebuild
./existential.sh flow off newsletter  # its machine off; services stay as they are
```

- `docker compose up -d` afterwards starts anything new.
- A flow that needs another turns that one on too.
- `off` never deletes a file you changed.

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

[Note → Automation](./note-to-automation) is part of Core, on whenever a chat model answers.

### Housekeeping

- **`clean-runs`** prunes `workspace/.decree/runs/` (logs also go to Loki when it's on).
- **`health-checks`** probes ntfy. For another service, copy its cron in
  `workspace/.decree/cron/` to `health-check-<slug>.md` and set `SERVICE_NAME` and `SERVICE_URL`
  (`http://<container>:<port>/<health path>`).
- **`check-versions`** reports images that are behind. `./existential.sh run check-versions
  --update` patches the templates; then `./existential.sh && docker compose pull && docker
  compose up -d`.
- **`hermes-knows-decree`** writes `workspace/ai/decree/` hourly, so Hermes (which can't see
  `.decree/`) knows what it may ask decree to run.

## How every flow works

Every flow has four parts:

```
  input  →  judgment  →  work  →  output
```

1. **Input.** A file, an email, your voice, a webhook, a schedule. Each becomes a message in one
   queue.
2. **Judgment.** One cheap question: is this worth acting on? Most things aren't.
3. **Work.** The expensive part, only for what passed: transcribe, research, extract, draft, file.
4. **Output.** A note, a task, a budget line, a notification, or another message.

:::tip[Don't skip judgment]
Without it, the expensive step runs on everything and you get a folder of unread reports.
:::

## The four knobs

The four parts are what you change, and three are settings, not code:

| Knob | What it is | How you change it |
|---|---|---|
| **Input** | What triggers the flow | Pick a trigger: a cron file, a webhook endpoint, a file-processor `PATTERN`, an inbox drop |
| **Judgment** | What counts as worth acting on | One line of prompt in cron frontmatter — e.g. `TRIAGE_CRITERIA` |
| **Work** | What actually gets done | The name of the routine to chain — e.g. `TRIAGE_ROUTINE` |
| **Output** | Where the result lands | A destination setting, or the routine you chained |

Each knob changes independently. [Note → Action](./note-to-action) walks through all four. A
new flow is one more routine: [Writing an Automation](../writing-a-routine).

## By kind

### Capture

- [Camera → OCR](./image-ocr): a photo's text
- [Note → Automation](./note-to-automation): write "next time I…, do…" and it offers to automate it
- [Your Own Newsletter](./newsletter): a weekly issue from feeds you picked
- [Note → Action](./note-to-action): an idea worth chasing is researched, with questions for you
- [Note → Connection](./note-connect): a new note is linked to related earlier ones

### Voice

- [Recording → Transcription](./recording-transcription): speaker-labelled transcripts
- [AutoVoice](./autovoice): a spoken phrase triggers a routine
- [HAwake](./hawake): train your own wake word
- [HAwake → Home Assistant → Tasker](./hawake-homeassistant): wake word to phone action

### Money

- [Bank Alert → Gmail → Budget](./transaction-gmail-actual-budget): transaction emails become budget entries

## Building your own

Every flow is a routine plus a trigger.

- **[Writing an Automation](../writing-a-routine)**: a routine's parts, its triggers, and chaining.
- **[Note → Action](./note-to-action)**: a worked example, four routines in one flow.
- **[Build On It](../build-on-it)**: reaching the stack over HTTP from outside.
- **[File Processor](../decree/file-change-processing)**: how a file landing in storage starts a routine.
