---
sidebar_position: 1
---

# Flows

:::info[One job, end to end]
One job traced through the services it touches. Back to [Services](../how-it-works.md), or on
to [Plugins](../plugins/index.md) to write your own.
:::

A flow is one job, from *something happened* to *it was handled*: a recording becomes a
transcript, a receipt becomes a budget entry. It is not a thing the stack has: it is a recipe,
written down here. Each one is the services and the plugins it turns on, and what is left for you.

## Turning one on

A plugin is a decree machine, a file in `automation/plugins/`, and none of them is on until you
say so. What each decree project has on is its own list, `.decree/plugins/.on`, which only these
commands change:

```bash
./existential.sh plugin                    # every plugin; on, and + for one something on needs
./existential.sh plugin on newsletter      # on, with all it needs, installed now
./existential.sh plugin off newsletter     # off; what it needed goes too, unless something else on needs it
./existential.sh service on whisperx       # a service a flow uses, then docker compose up -d
```

- A plugin's `x-exist-project` says where it runs: `automation` (the workspace's daemon),
  `backup` (automation-backup's, with the whole of `volumes/`), or `host` (a decree daemon on the
  host itself, the checkout's own `.decree`; `./existential.sh` says so until one runs).
- `off` never deletes what is yours: a machine's store, an edited cron file, your notes.
- Every project prunes its finished runs after 30 days (decree's `decree_prune`), and has
  `notify`, whatever is on.

| Flow | What it does | Turn on |
|---|---|---|
| You were here | Every morning, yesterday in one notification ([more](../getting-started.md#you-were-here)). **On by default** | `./existential.sh plugin on you_were_here` |
| Health checks | Probes where your notifications go every 15 minutes, and tells your phone when it stops ([more](#housekeeping)). **On by default** | `./existential.sh plugin on service_health` |
| Note → Automation | [Write "next time X, do Y" in a note](./note-to-automation.md), accept what is proposed, and it runs. **On by default** | `./existential.sh plugin on note_watch reconcile` |
| File advice | [Each file you add](#file-advice) is read once; your phone hears which plugin, or new machine, would handle it. **On by default** | `./existential.sh plugin on file_advise` |
| Look back | The week and the month in review, next to your notes ([more](../getting-started.md#look-back)) | `./existential.sh plugin on look_back` |
| Capture | What you type to an agent, and anything you POST, in one stream in `workspace/.capture/` ([more](../getting-started.md#capture)) | `./existential.sh plugin on capture` |
| Your own newsletter | [Mondays, at most seven items from feeds you picked](./newsletter.md) | `./existential.sh plugin on newsletter` |
| Gmail | New mail every 15 minutes, as decree messages ([Gmail](../integrations/gmail.md)) | `./existential.sh plugin on gmail_sync` |
| Bank alerts become budget entries | [The alert email for each charge becomes an Actual Budget transaction](./transaction-gmail-actual-budget.md) | `./existential.sh service on actual-budget` and `./existential.sh plugin on gmail_sync` |
| The note you meant to come back to | [Each new note is asked one question, worth doing?](./note-to-action.md) | `./existential.sh service on nextcloud` and `./existential.sh plugin on note_triage` |
| Notes that find their own connections | [A new note is checked against everything you wrote](./note-connect.md) | `./existential.sh plugin on note_connect` |
| Files from your phone start work | An upload through Nextcloud runs every [file processor](../decree/file-change-processing.md) whose pattern matches | `./existential.sh service on nextcloud automation-webhook` and `./existential.sh plugin on nextcloud_file_events` |
| Photograph it, and the text is yours | [A photo's text, written beside it](./image-ocr.md) | as above, and `./existential.sh plugin on ocr` |
| Voice memos you actually read | [Recordings become speaker-labelled transcripts](./recording-transcription.md) | as above, `./existential.sh service on whisperx` and `./existential.sh plugin on transcribe` |
| Workspace agent | A file matching your criteria is handed to an agent, and its answer lands in `ai/` | as above, and `./existential.sh plugin on agent_handoff` |
| Notes to Dropbox | Every 10 minutes, your Nextcloud notes compiled, indexed and pushed to Dropbox | as above, and `./existential.sh plugin on notes` |
| Your calendar, readable by agents | Nextcloud's calendar app on, and every event mirrored into the workspace as a note | `./existential.sh service on nextcloud` and `./existential.sh plugin on calendar_extract` |
| Office documents | [Word, Excel and PowerPoint in the browser](../storage/collabora.md) | `./existential.sh service on nextcloud collabora` and `./existential.sh plugin on nextcloud_richdocuments` |
| Local models | [Ollama](../ai/ollama.md) pulls your tier's models, once, as soon as it is up | `./existential.sh service on ollama` and `./existential.sh plugin on ollama_pull` |
| Talk to the house | [Home Assistant](../services/homeassistant.md), speech in and out, your chat model answering | `./existential.sh service on homeassistant wyoming-whisper wyoming-piper` and `./existential.sh plugin on homeassistant_voice` |
| Photos | [Immich](../services/immich.md), its admin made and your NAS photos indexed read-only | `./existential.sh service on immich` and `./existential.sh plugin on immich_setup` |
| Images and video on your own card | [ComfyUI workflows a decree message runs](../ai/comfyui.md) | `./existential.sh service on comfyui` and `./existential.sh plugin on comfy` |
| Plugin sharing | [Trade plugins with another stack](../plugins/index.md#between-stacks): ask for one, send yours when asked | `./existential.sh service on automation-webhook` and `./existential.sh plugin on plugin_share plugin_offer` |
| Report host | [This host, reported to your controller](../hosting/controller-and-workers.md): disks, CPU, RAM, VRAM, automations, runs, in Grafana | `./existential.sh plugin on report_host` (host) |
| Pull existential | [Follow the branch](../hosting/updates.md): `git pull`, `./existential.sh`, `docker compose up -d` every 15 minutes | `./existential.sh plugin on pull_existential` (host) |
| Boot daemon | [Your `.decree/boot.sh`](../hosting/host-daemon.md#boot-daemon), run once when the host daemon starts | `./existential.sh plugin on boot_daemon` (host) |
| Version updates | [Fridays at noon, every pinned image with a newer version upstream](../hosting/updates.md#pinned-images), in one notification | `./existential.sh plugin on check_versions` (host) |
| Update Ubuntu | [Keep an Ubuntu host patched](../hosting/updates.md#ubuntu): security updates daily, the rest weekly, a reboot at 02:00 only when one is required | `./existential.sh plugin on update_ubuntu` (host) |
| Lease GPU | [A GPU box's llama.cpp, Strata, ComfyUI and TTS take turns on its one card](../hosting/ai-box.md#one-card-taken-in-turns): a lease unloads the others first | `./existential.sh plugin on lease_gpu` (host) |
| Triage | Every enabled service's own check, run for you; your phone hears when one breaks or recovers | `./existential.sh service on automation-backup` and `./existential.sh plugin on triage` |
| Workspace sync | `workspace/` kept the same as one other copy, on your NAS or in Nextcloud, every minute | `./existential.sh service on automation-backup` and `./existential.sh plugin on workspace_sync` |
| Notes pull | An outside notes vault pulled into `workspace/notes/` every 15 minutes | `./existential.sh service on automation-backup` and `./existential.sh plugin on notes_pull` |
| Backups | [Every service's volumes and databases](../decree/automation-backup.md), nightly and weekly, to your rclone remote | `./existential.sh service on automation-backup` and `./existential.sh plugin on volume_backup db_backup sqlite_backup` |

Search ([qmd](../ai/qmd.md)) is part of Core: nothing to turn on.

## After turning one on

What only you can do, for the ones that need it. A plugin's cron files are installed once, into
`.decree/machines/<plugin>/cron/` of the project it runs in, and are yours to edit from then on.

- **You were here** runs at 07:00 with a chat model (`EXIST_MODEL_URL`); with none it still
  writes the parts built from files.
- **Look back** runs Sunday evenings for the week and on the last evening of each month for the
  month. For a year, ask: `echo | docker exec -i automation decree emit --machine look_back --param period=year`.
- **Capture**: `POST /capture` on automation-webhook appends to the stream; code-server's agents
  append every prompt you type, secrets redacted.
- **Your own newsletter**: list your feeds in `workspace/.decree/store/newsletter/feeds.txt` and say
  what you care about in `taste.md` beside it. To write an issue now:
  `echo | docker exec -i automation decree emit --machine newsletter`.
- **Gmail**: grant read-only access once, in a browser: `./existential.sh run automation gmail-sync`.
- **Bank alerts**: make a budget file (`./existential.sh run actual-budget setup`), label your
  bank's alerts in Gmail and record the label (`./existential.sh run automation gmail-labels`),
  copy `workspace/.decree/lib/actual-budget/parse-chase.ts` for your bank, then wire the label to
  an account: `./existential.sh run automation gmail-transactions-cron`.
- **The note you meant to come back to**: the first run records your notes as seen without
  judging them. `TRIAGE_CRITERIA` in `machines/note_triage/cron/note-triage.md` is the whole
  judgment; run with `TRIAGE_DRY_RUN: true` for a few days first. To judge the backlog once:
  `echo | docker exec -i automation decree emit --machine note_triage --param TRIAGE_BOOTSTRAP=true`.
- **Files from your phone**: sync the workspace folder with the Nextcloud desktop client, logging
  in at `https://nextcloud.<domain>` with the admin login in `nas/nextcloud/.env`. Only uploads
  through Nextcloud fire. To write your own processor, copy
  `workspace/.decree/lib/file-processors.example/example.sh` to `file-processors/<name>.sh`.
- **Photograph it** uses `EXIST_MODEL_VISION` at your model's address; with a local ollama,
  `ollama_pull` pulls it.
- **Voice memos**: speaker labels need a HuggingFace token. Accept the model terms at
  https://huggingface.co/pyannote/speaker-diarization-community-1; WhisperX's setup asks for the
  token (`WHISPERX_HF_TOKEN`).
- **Workspace agent**: `CRITERIA` in the processor (`file-processors/agent-handoff.sh` in
  `automation/plugins/agent_handoff.md`) is the whole judgment. It is code, so it is changed
  there, on the host, and `./existential.sh` installs it; nothing in the workspace can.
- **Notes to Dropbox**: add the Dropbox remote once, `./existential.sh run rclone`.
- **Your calendar**: set `CALENDAR_EXTRACT_TZ` in `machines/calendar_extract/cron/calendar-extract.md`
  to your own zone (e.g. `America/Denver`) so times read right.
- **Local models**: the models are named once, in `.env.shared`'s Model Selection block; change them
  with `./existential.sh run models`. To pull in the foreground: `./existential.sh run ollama pull-models`.
- **Talk to the house**: the order files make the admin account and the Assist pipeline once Home
  Assistant answers. Then, at `https://homeassistant.<domain>`, Settings → Voice assistants, and add
  your devices from Home Assistant's own UI.
- **Photos**: the order file makes the Immich admin (your `EXIST_EMAIL` and `EXIST_PASSWORD`) and
  adds your NAS photos as a read-only External Library. Sign in at `https://immich.<domain>`; the
  phone app takes the same login.
- **Images and video**: ComfyUI ships with no models: each workflow in
  `workspace/.decree/lib/comfy/workflows/` names the files it needs and where they go. To run one,
  drop one of `comfy`'s examples (`x-exist-examples` in `automation/plugins/comfy.md`) into
  `volumes/workspace_data/.decree/inbox/`, or
  `echo 'a lighthouse at dusk' | docker exec -i automation decree emit --machine comfy --param type=image-text-image`.
  Already run ComfyUI on a GPU box? Offer it there (`lease_gpu`) and leave it off here: `comfy`
  leases it.
- **Plugin sharing**: nothing is installed by an offer. What another stack sends lands in
  `workspace/ai/proposed/`, for you to read and move into `.decree/plugins/`. Which of your machines
  go out without asking is `PLUGIN_SHARE_ALLOW`; every other one asks your phone first.
- **The host plugins** run in a decree daemon on the host (the checkout's own `.decree`): start
  one, and have it start at boot, as [the host daemon](../hosting/host-daemon.md) says.
  `report_host` reports to `EXIST_CONTROLLER` in `.env.shared` (blank: this host is the controller,
  and its own Loki has to be on). `boot_daemon` runs `.decree/boot.sh`, one line per process
  (`tmx -d comfyui 'cd ~/ComfyUI && exec .venv/bin/python main.py --listen 0.0.0.0'`).
  `update_ubuntu` needs root once: `sudo bash .decree/lib/update_ubuntu/setup.sh`. `lease_gpu`
  reads `AI_BOX_*` in that box's `.decree/.env` ([GPU box](../hosting/ai-box.md)). When
  `check_versions` names an image: `./existential.sh run check-versions --update`, then
  `./existential.sh && docker compose up -d`.
- **Triage**: nothing is configured per service; what is on in `.env.shared` is what is checked.
- **Workspace sync** does nothing until it has a NAS folder (`EXIST_NFS_SHARE_WORKSPACE`) or
  Nextcloud keys in `.env`.
- **Notes pull**: set `NOTES_PULL_SOURCE` in
  `services/automation-backup/machines/notes_pull/cron/notes-pull.md` to your real
  `user@host:/path/` and add the key it describes, or to `/notes-nas/` for a NAS folder. Until then
  every run fails and says so.
- **Backups** go to the rclone remote in `EXIST_BACKUP_RCLONE_REMOTE` (add it once with
  `./existential.sh run rclone`); restore with `./existential.sh run backup-restore`. Each backup
  plugin's cron files list every service it knows; one that is off here is skipped. Delete a line
  to stop backing one up.

### File advice

Every file you add or change outside `ai/` and hidden folders is read once, with the list of
plugins: by Claude (Haiku, in plan mode, so it can change nothing) once you have signed in to
`claude` in code-server's terminal, else by your chat model. If a plugin that is off fits it, or
a machine nobody has written yet would plainly be wanted, your phone hears it: the plugin's
`./existential.sh plugin on` line, or the machine to ask claude or opencode for. Each suggestion is
sent once, so a folder of PDFs is one message.

It starts from now: when it is installed, everything already in the workspace is marked as
handled without being read, and a file already read is not read again when it changes.
`workspace/.decree/store/file_advise/` holds `handled.txt` and `suggested.txt`; deleting a
line reads that file, or sends that suggestion, again.

### Housekeeping

- **`decree_prune`**, in every project, prunes finished runs older than 30 days, every Sunday at
  03:00 (`PRUNE_OLDER_THAN` in the project's `.env` changes the age). Every run is shipped to
  Loki too, when it is on, so this prunes a local copy, not the history.
- **`service_health`** probes ntfy. For another service, copy its cron,
  `workspace/.decree/machines/service_health/cron/health-checks.md`, into a
  [schedules plugin of your own](../plugins/writing-a-plugin.md#cron--on-a-schedule) as
  `health-check-<slug>.md`, set `SERVICE_NAME` and `SERVICE_URL`
  (`http://<container>:<port>/<health path>`), and accept it.

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

Each knob changes independently. [Note → Action](./note-to-action.md) walks through all four.

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

A flow of your own is the plugins that do the work, turned on. A new kind of work is a new plugin.

- **[Writing a Plugin](../plugins/writing-a-plugin.md)**: a machine, its scripts, its triggers, and chaining.
- **[Note → Action](./note-to-action.md)**: a worked example, four machines in one flow.
- **[Over HTTP](../plugins/http.md)**: reaching the stack from outside.
- **[File Processor](../decree/file-change-processing.md)**: how a file landing in storage starts a machine.
