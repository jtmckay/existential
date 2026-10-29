---
sidebar_position: 2
---

# Getting Started

## Prerequisites

- [Docker](https://www.docker.com/get-started/), usable without sudo
  (`sudo usermod -aG docker "$USER"`, then log out and back in). `existential.sh` refuses to run
  under sudo.
  - The stack starts with the machine. For rootless Podman, `existential.sh` turns on its restart
    service and linger, and warns if Docker itself isn't set to start at boot.
  - Docker Desktop: turn on "Start Docker Desktop when you sign in".
- A machine to host it (see [Hosting](./hosting/)): Linux, or a Mac with Docker Desktop.
  - Windows: run everything inside WSL2. Clone the repo on the Linux side (not under `/mnt/c`)
    and install Tailscale inside WSL.
- For Core, [Tailscale](https://tailscale.com/download), logged in on that machine and on every
  device that should reach it. Without it, see
  [Reaching it without Tailscale](#reaching-it-without-tailscale).
- The repo:
  ```
  git clone https://github.com/jtmckay/existential.git
  cd existential
  ```

## Setup

```bash
./existential.sh
docker compose up -d
```

The first run asks for a username and password and builds **Core**. No GPU, no model downloads.

| | |
|---|---|
| **Access** | Tailscale on the host: HTTPS on every device you log in |
| **Workspace** | code-server (editor + terminal over the work dir) |
| **Automation** | Decree (the automation daemon), ntfy (where automations report in) |

Four [flows](./flows/) are on by default: the [morning digest](#you-were-here), the
[look backs](#look-back), run cleanup, and a health check on ntfy.

Core ships no backups. Turn on [automation-backup](./decree/automation-backup), or put
`volumes/workspace_data` under git with a remote you choose.

### Turning on more

```bash
./existential.sh flow                 # pick from the list
./existential.sh flow on newsletter   # or by name
```

A **flow** is one thing the stack does for you: your own newsletter, transcribed voice memos,
bank alerts as budget entries.

- `flow on` turns on the services it needs and its machine, rebuilds, and prints any step only you
  can do (an OAuth grant, a password).
- `docker compose up -d` starts what is new.
- `flow off <name>` turns the machine off and leaves the services alone.
- The full list: [Flows](./flows/#turning-one-on).

A service no flow needs (Caddy, Grafana, Mealie, ...) is one flag in `.env.shared`,
`EXIST_IS_<CATEGORY>_<SLUG>=true`, then `./existential.sh` again.

What each `./existential.sh` run does:

1. Renders every `*.exist.*` template, prompting for `EXIST_CLI` values and generating passwords
   and keys
2. Runs each enabled service's `exist.initial.sh` (certs, caches, seed config)
3. Generates one `docker-compose.yml` from every enabled service
4. Generates the root `.env` from `.env.shared` and every enabled service's `.env`

With Tailscale up, it also runs `tailscale serve`:

- code-server at `https://<machine>.<tailnet>.ts.net`, ntfy at `:8443`, with a Let's Encrypt
  certificate.
- Both containers publish on loopback only, so only your tailnet can connect.
- The name is saved as `EXIST_TAILNET_NAME`, which ntfy and the digest's links use.
- The name appears in public certificate transparency logs (visible, not reachable).

If Tailscale can't serve yet, the run prints what is missing and carries on:

- **MagicDNS** and **HTTPS Certificates** on in the [admin console](https://login.tailscale.com/admin/dns)
- `sudo tailscale set --operator=$USER`, once. The script never runs sudo itself.

### Reaching it without Tailscale

Turn on [Caddy](./hosting/caddy) (`EXIST_IS_HOSTING_CADDY=true`). Every service gets
`https://<slug>.<domain>`, with certificates from Caddy's own CA, trusted once per device.

- `EXIST_DOMAIN` defaults to `<lan-ip-with-dashes>.nip.io`: public wildcard DNS that resolves on
  any device on your network with no setup.
- If Tailscale is up, the tailnet IP is used instead, so the names work across your tailnet.

:::warning
Don't set `EXIST_DOMAIN` to a MagicDNS name like `my-box.tailnet.ts.net`. MagicDNS resolves that
node name only, so every `<slug>.` under it fails. Use the tailnet **IP** in nip.io form.
:::

From outside the house: a VPN back to your network, or a piHole on another server. See
[VPN](./hosting/vpn.md).

### The hardware questions

Asked once, by the run that enables the first service that needs a GPU (Ollama, ComfyUI, …).
Core never asks.

- **GPU vendor**: `nvidia`, `amd` (Vulkan/ROCm), `none` (CPU), or `external`: models live on
  another machine and no Ollama runs here. Point `EXIST_MODEL_URL` at any OpenAI-compatible `/v1`
  server.
- **VRAM** picks the model tier. Each model role can live on a different machine:
  [Configuration](./configuration.md#endpoints--putting-roles-on-different-machines).

Re-ask both with `./existential.sh run models`.

### Upgrading

`git pull && ./existential.sh`. Rendered files are never overwritten, except:

- New template keys are appended to your `.env` files and listed.
- Newer service images are listed, and updated in your compose files if you say yes.

Every run also pulls and builds the images, without touching what's running. The next
`docker compose up -d` switches to them. See
[what happens when you `git pull`](./configuration.md#what-happens-when-you-git-pull).

## Enable/Disable Services

A flow turns on what it needs. For anything else, set flags in `.env.shared`:

```bash
EXIST_IS_AI_OLLAMA=true
EXIST_IS_SERVICES_NOCODB=false
```

Then run `./existential.sh`. It renders templates for newly enabled services and leaves existing
files alone.

## Deploy

```bash
docker compose up -d
```

Open code-server at `https://<machine>.<tailnet>.ts.net`. That is the [workspace](#workspace);
start `claude` in its terminal.

Decree waits for each migration's service to pass its `exist.test.sh`, then runs the migration.
To see what is working:

```bash
./existential.sh test services      # every enabled service validates itself
./existential.sh run footprint      # memory limits vs actual use
```

With [automation-backup](./decree/automation-backup) on, **triage** runs those checks on a schedule
and notifies you when something breaks or recovers.

### Logging in

- Most services use `EXIST_USERNAME` / `EXIST_PASSWORD`, asked on the first run (Enter generates
  a password) and stored in `.env.shared`. See
  [Identity and permissions](./configuration.md#identity-and-permissions).
- Edit `.env.shared` or a service's own `.env`, never the root `.env`: it is regenerated every run.
- After a change: `./existential.sh`, then `docker compose up -d`.

## Workspace

`workspace/` (in `volumes/workspace_data`) is your directory:

- **`notes/`**: your notes, plain markdown. Starts with `my-first-note.md`.
- **`.decree/`**: your automations, run by the `automation` daemon on the next tick. The repo's
  machines are copied in once, so your edits win. `graph/` draws every machine. See
  [Writing a routine](./writing-a-routine).
- **`ai/`**: what automations write, indexed like everything else.
- **`.capture/`**: everything you typed to an agent. See [Capture](#capture).
- **`ai/you-were-here.md`**: the morning digest, with one file per day under
  `ai/you-were-here/<YYYY>/`. See [You were here](#you-were-here).

In Core, [code-server](./services/code-server) opens it at `/workspace` with `claude` and
`opencode` in the terminal. The workspace carries the decree skill in `.claude/skills/decree/`,
so `claude` there already knows how to write an automation. Add-ons mount the same tree:
[Nextcloud](./storage/nextcloud) as its `workspace` folder, [Hermes](./ai/hermes) at
`/opt/data/workspace`.

- **A file change can start an automation.** A handler in `.decree/handlers.yml` runs once the
  file has been quiet for 30 seconds. A `.gitignore`'d path or anything in `.git/` never does.
  See [File Handlers](./decree/file-handlers).
- **With Local AI on**, [OpenViking](./ai/openviking) indexes the workspace every 15 minutes and
  Hermes can search it.
- **To edit on other machines**, sync it: the Nextcloud desktop client with Nextcloud in the stack,
  or [a Nextcloud elsewhere](#syncing-with-a-nextcloud-optional). Its *Ignored Files* list keeps
  files off the server.

### Capture

`workspace/.capture/` keeps what you typed to an agent, one JSON line each (`ts`, `source`,
`context`, `session`, `text`), one file per writer and month (`2026-10-code-server.jsonl`).

- Only what you typed: never a response, tool output or transcript.
- Secrets (API keys, tokens, `password=`-style assignments, private keys) are replaced with a
  marker such as `[REDACTED:anthropic-key]` before writing.
- It never blocks the prompt. Failures go to `workspace/.capture/errors.log`.
- Prompts with a session id are also appended to
  `workspace/ai/conversations/<date>-<tool>-<session>.md`, so [search](./ai/qmd) finds them.
- One script does it all: `automation/lib/capture/capture.sh` (bash and `jq`).

| Source | On | Off |
|---|---|---|
| Claude Code in [code-server](./services/code-server) | By default: a `UserPromptSubmit` hook | `CODE_SERVER_CAPTURE=false` in `services/code-server/.env`, then `./existential.sh && docker compose up -d code-server` (turns off opencode too) |
| opencode in code-server | By default: a plugin, `automation/lib/capture/opencode.ts` | The same key |
| Claude Code on another machine | `bash automation/lib/capture/capture.sh install <workspace dir>` from a checkout, with the workspace synced there | `bash automation/lib/capture/capture.sh uninstall` |
| Anything that can POST | `POST /capture` on `automation-webhook` (`EXIST_IS_SERVICES_AUTOMATION_WEBHOOK=true`) | Delete `/capture` from `workspace/.decree/decree-go-rest.yml` |

`install` adds the hook to `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR`'s) beside your
other hooks; `uninstall` removes only that one.

```bash
curl -X POST https://automation-webhook.<domain>/capture \
  -H "Authorization: Bearer $AUTOMATION_WEBHOOK_SECRET" \
  --data-binary '{"source":"phone","text":"buy filters"}'
```

- Body: `{"source", "text"}` JSON (optional `context`), or plain text, filed as source `webhook`.
- The secret is `AUTOMATION_WEBHOOK_SECRET` in `services/automation-webhook/.env`.
- Without the webhook: `cd /workspace && echo 'buy filters' | decree emit --machine capture` in
  code-server's terminal.
- An older install: copy the `/capture` entry from `automation/decree-go-rest.yml` into
  `workspace/.decree/decree-go-rest.yml`.

### You were here

Every morning at 7, `you_were_here` writes `workspace/ai/you-were-here.md` and pushes the top of
it to ntfy:

- **The picture**: two or three sentences.
- **Waiting on you**: at most three, from `.decree/attention/` and runs waiting on a person.
- **One next thing.**
- **Holding steady**: machines whose last run succeeded, and the active schedules.
- **Where you left off**: the last prompt of each agent session, by project, from
  [capture](#capture).
- **From your feeds**: only if `workspace/notes/feeds.md` exists. Three to five new items from
  those feeds closest to your work, each shown once, never one a note already links to.
- **Worth learning**: one Wikipedia article on a subject you've been looking into, never repeated
  and never one a note links to. Only the subject phrase is sent to Wikipedia. Set the machine's
  `wikipedia` param to another edition (`de`, `fr`), or blank to turn it off.
- **Everything else** (note only): decisions in `notes/decisions/`, captured prompts that read like
  decisions, touched notes with open checkboxes, schedules, and changes since the last digest.

Details:

- The chat model writes The picture, One next thing, feed reasons and the Worth learning subject,
  linking each claim to its source. Everything else is built from files. Without a model, those
  sections are left out.
- The push is cut to fit ntfy's 4096 bytes, and skipped when nothing changed.
- Each day is kept as `workspace/ai/you-were-here/<YYYY>/<YYYY-MM-DD>.md`, with a **Done**
  section. Past days are never rewritten. **Worked on** lines name their capture source, which
  [work look backs](#look-back) filter on.
- Schedule: `workspace/.decree/cron/you-were-here.md`. Off: `./existential.sh flow off you-were-here`.
- Now: `POST /you-were-here` on `automation-webhook`, or `echo | decree emit --machine you_were_here`
  in code-server's terminal. `note_link` sets the push's last line.
- An older install: copy `/you-were-here` from `automation/decree-go-rest.yml` into
  `workspace/.decree/decree-go-rest.yml`.

### Look back

`look_back` reads a range of day notes, writes
`workspace/ai/you-were-here/<YYYY>/look-back-<from>-<to>.md`, and sends a short ntfy:

- **Highlights**: checkboxes ticked, notes created, migrations landed, by project.
- **Themes**: projects that came up on more than one day.
- **Decisions made**: notes in `notes/decisions/` and machines that landed.
- **By the numbers**: counts only.
- **In short**: a paragraph from the chat model, when one is reachable.

Every item links to its day note.

- Default range: year to date. `period` (`week`, `month`, `quarter`, `year`) ends at `to` (today
  when blank); `from`/`to` (`YYYY-MM-DD`) set either end.
- `scope=work` keeps only what `workspace/ai/you-were-here/scope.md` lists (projects, folders,
  capture sources), and writes `…-work.md` beside the full one.
- Weekly (Sunday) and monthly (month-end) look backs are on by default
  (`cron/look-back-weekly.md`, `look-back-monthly.md`). Longer ranges read those instead of
  every day note.
- With the webhook: `POST /look-back`, `/look-back/month`, `/look-back/month/work`.
- An older install: copy the `/look-back` entries from `automation/decree-go-rest.yml`.

```bash
docker exec automation decree emit --machine look_back --param period=quarter --param to=2026-09-30 </dev/null
```

### Syncing with a Nextcloud (optional)

With [automation-backup](./decree/automation-backup) on and the keys set, `workspace-sync` runs
`rclone bisync` with a Nextcloud folder every five minutes, both ways.

- Keys, in `.env`: `EXIST_NEXTCLOUD_DOMAIN`, `EXIST_NEXTCLOUD_USER`,
  `EXIST_NEXTCLOUD_APP_PASSWORD` (from Nextcloud's *Settings → Security*). Folder:
  `EXIST_NEXTCLOUD_WORKSPACE_DIR`, default `workspace`. Blank keys: nothing syncs.
- Never synced: anything a `.gitignore` under `workspace/` ignores, and every `.git/`.
- WebDAV drops file modes, so each sync marks `workspace/.decree/scripts/` executable again.
- A sync that would delete over half the files on one side deletes nothing and waits for
  `docker exec automation-backup decree event <wait id> delete` (or `keep`).
- With Nextcloud in this stack, its `workspace` folder already is this tree. Point
  `EXIST_NEXTCLOUD_WORKSPACE_DIR` elsewhere for a second copy.

### Bringing in real notes (e.g. an Obsidian vault)

- Simplest: keep the vault inside `workspace/`.
- To edit it on other devices: sync through Nextcloud, see [Obsidian](./services/obsidian).
- To pull it in from elsewhere (with automation-backup on): copy
  `services/automation-backup/cron.example/notes-pull.md` to `services/automation-backup/cron/`,
  set `NOTES_PULL_SOURCE` to an rsync-over-SSH path (`user@nas:/path/to/vault/`), and put an SSH
  key at `automation/secrets/notes-pull/id_ed25519`. Pulls are additive unless
  `NOTES_PULL_DELETE=true`. Pulled files fire no Nextcloud events.

## Integrations

```bash
./existential.sh run automation gmail-sync   # Gmail OAuth
./existential.sh run rclone                  # Remote file storage
```

See [Integrations](./integrations/). `./existential.sh run` lists every action.
