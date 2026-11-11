---
sidebar_position: 1
---

# Flows

:::info[Level 3 of 4 · Components]
One job traced through the services it touches. Back out to [Level 2 · Services](../how-it-works.md),
or go on to [Level 4 · Plugins](../plugins/index.md) to write your own.
:::

A flow is one job, from *something happened* to *it was handled*: a recording becomes a
transcript, a receipt becomes a budget entry.

## Turning one on

Each flow is a file in `automation/plugins/flows/`: the services it needs, the automations it
turns on, and any step only you can do. What you have on is one list, `workspace/.decree/plugins.yml`.

```bash
./existential.sh flow                 # pick from the list; ✓ marks the ones on
./existential.sh flow on weekly-newsletter   # asks for each service it needs, into plugins.yml, then a rebuild installs it
./existential.sh flow off weekly-newsletter  # out of plugins.yml; services stay as they are
```

- `docker compose up -d` afterwards starts anything new.
- A flow that needs another turns that one on too.
- `off` never deletes a file you changed.
- `worker` and `auto-update` run on the host itself, in a decree daemon there (`host/.decree`),
  not in a container. `./existential.sh` says so until one runs.

| Flow | What it does | Needs, beyond Core |
|---|---|---|
| `you-were-here` | Every morning, yesterday in one notification. **On by default** | a chat model |
| `look-back` | The week and the month in review, next to your notes. **On by default** | a chat model |
| `clean-runs` | Prunes decree's finished run logs after a week. **On by default** | — |
| `health-checks` | Probes a service every 15 minutes, and tells your phone when it stops. **On by default** | — |
| `note-to-automation` | [Write "next time X, do Y" in a note](./note-to-automation.md), accept what is proposed, and it runs. **On by default** | a chat model |
| `capture-stream` | What you type to an agent, and anything you POST, in one stream in `workspace/.capture/`. **On by default** | — |
| `code-server-agents` | claude, opencode and pi in code-server's terminal, pi on your own model. **On by default** | — |
| `weekly-newsletter` | [Your own newsletter](./newsletter.md) from only the feeds you picked | a chat model |
| `check-versions` | Mondays, the services with a newer image | — |
| `search` | Your notes, PDFs and Word files, by meaning and by words ([qmd](../ai/qmd.md)) | qmd |
| `gmail-inbox` | New mail every 15 minutes, as decree messages ([Gmail](../integrations/gmail.md)) | a Google grant |
| `budget` | [Bank alerts become budget entries](./transaction-gmail-actual-budget.md) | Actual Budget, `gmail` |
| `note-triage` | [The note you meant to come back to](./note-to-action.md) | Nextcloud, a chat model |
| `knowledgebase` | The workspace indexed into OpenViking, so pi answers from it | OpenViking |
| `note-connect` | [Notes that find their own connections](./note-connect.md) | `knowledgebase` |
| `nextcloud-capture` | A file uploaded through Nextcloud runs the [file processors](../decree/file-change-processing.md) | Nextcloud, automation-webhook |
| `image-ocr` | [A photo's text, written beside it](./image-ocr.md) | `nextcloud-capture`, a vision model |
| `transcription` | [Recordings become speaker-labelled transcripts](./recording-transcription.md) | WhisperX, `nextcloud-capture` |
| `workspace-agent` | A file matching your criteria is handed to an agent | OpenViking, Firecrawl, `nextcloud-capture` |
| `notes-to-dropbox` | Nextcloud notes compiled and pushed to Dropbox | `nextcloud-capture`, a Dropbox remote |
| `calendar` | Nextcloud's calendar, every event mirrored into the workspace | Nextcloud |
| `office-documents` | Word, Excel and PowerPoint in the browser | Nextcloud, Collabora |
| `local-models` | Ollama on this machine pulls your tier's models, once | Ollama |
| `home-voice` | Talk to the house: Home Assistant, speech in and out, your chat model answering | Home Assistant, Wyoming |
| `photos` | Immich, its admin made and your NAS photos indexed read-only | Immich |
| `comfyui` | ComfyUI workflows a decree message runs | ComfyUI and its models |
| `worker` | [This machine reported to your controller](../hosting/controller-and-workers.md): disks, automations, runs, in Grafana | decree on the host |
| `auto-update` | [Follow the branch](../hosting/updates.md): `git pull`, `./existential.sh`, `docker compose up -d` every 15 minutes | decree on the host |

[Note → Automation](./note-to-automation.md) is part of Core, on whenever a chat model answers.

### Housekeeping

- **`clean-runs`** prunes `workspace/.decree/runs/` (logs also go to Loki when it's on).
- **`health-checks`** probes ntfy. For another service, copy its cron in
  `workspace/.decree/cron/` to `health-check-<slug>.md` and set `SERVICE_NAME` and `SERVICE_URL`
  (`http://<container>:<port>/<health path>`).
- **`check-versions`** reports images that are behind. `./existential.sh run check-versions
  --update` patches the templates; then `./existential.sh && docker compose pull && docker
  compose up -d`.

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
| **Work** | What actually gets done | The name of the machine to chain — e.g. `TRIAGE_ROUTINE` |
| **Output** | Where the result lands | A destination setting, or the machine you chained |

Each knob changes independently. [Note → Action](./note-to-action.md) walks through all four. A
new flow is one more plugin: [Writing a Plugin](../plugins/writing-a-plugin.md#making-it-a-flow).

## By kind

### Capture

- [Camera → OCR](./image-ocr.md): a photo's text
- [Note → Automation](./note-to-automation.md): write "next time I…, do…" and it offers to automate it
- [Your Own Newsletter](./newsletter.md): a weekly issue from feeds you picked
- [Note → Action](./note-to-action.md): an idea worth chasing is researched, with questions for you
- [Note → Connection](./note-connect.md): a new note is linked to related earlier ones

### Voice

- [Recording → Transcription](./recording-transcription.md): speaker-labelled transcripts
- [AutoVoice](./autovoice.md): a spoken phrase triggers a routine
- [HAwake](./hawake.md): train your own wake word
- [HAwake → Home Assistant → Tasker](./hawake-homeassistant.md): wake word to phone action

### Money

- [Bank Alert → Gmail → Budget](./transaction-gmail-actual-budget.md): transaction emails become budget entries

## Building your own

Every flow is a plugin with no machine, needing the plugins that do the work.

- **[Writing a Plugin](../plugins/writing-a-plugin.md)**: a machine, its scripts, its triggers, chaining, and making it a flow.
- **[Note → Action](./note-to-action.md)**: a worked example, four machines in one flow.
- **[Over HTTP](../plugins/http.md)**: reaching the stack from outside.
- **[File Processor](../decree/file-change-processing.md)**: how a file landing in storage starts a machine.
