---
sidebar_position: 2
---

# Getting Started

## Prerequisites

- [Docker](https://www.docker.com/get-started/), usable without sudo
  (`sudo usermod -aG docker "$USER"`, then log out and back in) — `existential.sh` refuses to run under sudo
- A machine to host the services (see [Hosting](./hosting/))
- For Core, [Tailscale](https://tailscale.com/download), installed and logged in on that machine
  and on every phone and laptop that should reach Core. Without it, see
  [Reaching it without Tailscale](#reaching-it-without-tailscale)
- Git clone the repo
  ```
  git clone https://github.com/jtmckay/existential.git
  cd existential
  ```

## Setup

```bash
./existential.sh quest
```

On a first run this asks two hardware questions and then offers **Core** — the whole loop
wired together, rather than forty checkboxes. Say yes and you get a work dir you open in a
browser, a terminal there to talk to an AI, decree to automate it, and ntfy to tell you. No GPU,
no model downloads:

| | |
|---|---|
| **Access** | Tailscale on the host (no container): real HTTPS on every device you log in |
| **Workspace** | code-server (editor + terminal over the work dir) |
| **Automation** | Decree (the automation daemon), ntfy (where automations report in) |

Everything else is an add-on, one unnumbered quest each: **Network** (Caddy hostnames, LAN
access without Tailscale), **Monitoring** (Dashy, Loki, Prometheus, Grafana, Uptime Kuma),
**Capture** (automation-webhook, Nextcloud), **Apps** (Actual Budget, Mealie, IT Tools),
**Local AI** and **Voice & Home**. Files, DNS, the house and GPU models usually run on other
servers anyway.

Core ships no backups. The simplest way to keep the workspace safe is to put
`volumes/workspace_data` under git, with a remote you choose.

Decline and you fall through to the full picker, then the quest list. The numbered quests there
are those same three rows one at a time — Core, taken apart — so you can build up to the same
stack in pieces and see every step instead of having it done for you. They cross themselves off
as you finish them, and running Core crosses off every one that can be checked from disk.
Everything unnumbered is an add-on, an integration or an automation past Core.

Either way, `./existential.sh` on its own does the same work without the questions:

1. Renders every `*.exist.*` template into its live counterpart, prompting for `EXIST_CLI` values
   and generating passwords and keys for the rest
2. Runs each enabled service's `exist.initial.sh` (pre-startup setup — certs, caches, seed config)
3. Generates a unified `docker-compose.yml` from all enabled services
4. Generates a master `.env` by merging `.env.shared` with every enabled service's `.env`

With Tailscale up on the host, it also serves Core over HTTPS on the machine's tailnet name with
`tailscale serve`: code-server at `https://<machine>.<tailnet>.ts.net` and ntfy at
`https://<machine>.<tailnet>.ts.net:8443`, with a Let's Encrypt certificate every device already
trusts. Both containers publish on the host's loopback only, so nothing in Core listens on the
LAN, and only devices on your tailnet can connect. The serve config survives a reboot, and
re-running `./existential.sh` doesn't duplicate it. It records the name as `EXIST_TAILNET_NAME`,
which ntfy's base URL and the links the stack sends (the morning digest) use.

That name appears in public certificate transparency logs, as every Let's Encrypt name does:
visible, not reachable.

Until Tailscale can serve, `./existential.sh` prints what is left and carries on: turning on
**MagicDNS** and **HTTPS Certificates** in the
[admin console](https://login.tailscale.com/admin/dns), and, once,
`sudo tailscale set --operator=$USER` so your user may configure serve. It never runs sudo itself.

### Reaching it without Tailscale

A host without Tailscale is outside Core. There, the **Network** quest adds Caddy:
`https://<slug>.<domain>` for every service, with certificates from its own CA, trusted once per
device, as that quest's guide explains. For that, `./existential.sh` fills in
`EXIST_LOCAL_HOST_IP` with this machine's LAN address and derives `EXIST_DOMAIN` as
`<that-ip-with-dashes>.nip.io`. nip.io is public wildcard DNS, so every `https://<slug>.<domain>`
resolves on any device with nothing configured, and every phone and laptop on the same network
reaches it. If Tailscale is up after all, its tailnet address is preferred instead, so the same
names work from every device on your tailnet.

:::warning
Don't set `EXIST_DOMAIN` to a MagicDNS name like `my-box.tailnet.ts.net`.
MagicDNS resolves that exact node name and nothing beneath it, so every `<slug>.` under it fails
to resolve. Use the tailnet **IP** in nip.io form — tailscale carries the traffic, nip.io
supplies the wildcard.
:::

To reach Caddy's names from outside the house, put your devices on a VPN back to your network
(WireGuard, OpenVPN, Tailscale, Headscale), or answer the domain with a piHole on another
server. The options sit side by side in [VPN](./hosting/vpn.md).

### The hardware questions

**GPU vendor** decides how models run: `nvidia` uses the container runtime, `amd` uses
Vulkan/ROCm, `none` is CPU-only, and **`external`** means the models live on another machine —
no card needed here, and no local Ollama. That last one is also how a GPU-less machine runs the
full agent path: point `EXIST_MODEL_URL` at a box that has the VRAM — ollama or llama.cpp,
anything that serves OpenAI's `/v1`.

**VRAM** picks the model tier. Every model the stack uses is named once, in `.env.shared`'s
*Model Selection* block, and each role can live on a different machine — see
[Configuration](./configuration.md#endpoints--putting-roles-on-different-machines).

Re-ask both later with:

```bash
./existential.sh run models
```

### Upgrading

`git pull && ./existential.sh` is the upgrade. Rendered files are never overwritten, so your
edits and generated secrets survive; any key that is new in a template is appended to your
`.env` files and named in the output. See
[what happens when you `git pull`](./configuration.md#what-happens-when-you-git-pull).

## Enable/Disable Services

Edit `.env.shared` and set services to `true` or `false`:

```bash
EXIST_IS_AI_OLLAMA=true
EXIST_IS_SERVICES_AUTOMATION=true
EXIST_IS_SERVICES_NOCODB=false
```

Then re-run to pick up the change:

```bash
./existential.sh
```

That regenerates `docker-compose.yml` and the master `.env`. It renders templates for services
you have just enabled, and leaves every file that already exists alone.

## Deploy

```bash
docker compose up -d
```

Services bring themselves up: Decree waits for the services its migrations target to pass their
`exist.test.sh`, then applies any one-time migrations. To see what is and is not working at any
point:

```bash
./existential.sh test services      # every enabled service validates itself
./existential.sh run footprint      # memory limits vs what is actually in use
```

Decree's **triage** routine runs the same checks on a schedule and notifies you when something
breaks or recovers, backing off as the stack stays green.

### Logging in

Most services log you in with `EXIST_USERNAME` / `EXIST_PASSWORD` — asked once on the first
run (press Enter at the password and one is generated for you), stored in `.env.shared`, and
seeded from there into every service that needs an admin account on first boot. Grab (or
change) them there. See [Identity and
permissions](./configuration.md#identity-and-permissions).

Only ever edit `.env.shared` (or a service's own `.env`), never the root `.env` — it's fully
regenerated by merging those two on every `./existential.sh` run (the file itself says so at the
top), so a direct edit is silently lost on the next render. After changing a value, re-run:

```bash
./existential.sh
```

to fold it into the root `.env`, then `docker compose up -d` to pick it up.

## Workspace

The workspace is *your* directory, `workspace/`: `notes/` for your notes (plain markdown; a
fresh install starts it with `my-first-note.md`) and `.decree/` for your automations. It lives
in `volumes/workspace_data`. In Core, [code-server](./services/code-server) opens it at
`/workspace`, with an editor and a terminal where `claude` and `opencode` are ready, and the
`automation` daemon runs what is in its `.decree/`. Start `claude` there and say what you want
automated: the workspace carries the decree skill in `.claude/skills/decree/`, refreshed when
the stack's decree changes, so it already knows how to write a machine. Nothing in the
workspace needs Nextcloud or [Obsidian](./services/obsidian); either is optional.
Add-ons mount the same tree: [Nextcloud](./storage/nextcloud) serves it as its **`workspace`**
folder and [Hermes](./ai/hermes) at `/opt/data/workspace`. Put notes, plans,
reference material — anything you want an agent to know about — there. Use it.

To edit it on your own machines, optionally sync it: with Nextcloud in the stack, the
**Nextcloud desktop client** (nextcloud.com/install) logs in at `https://nextcloud.<domain>` and syncs the
`workspace` folder; with a Nextcloud elsewhere, see
[below](#syncing-with-a-nextcloud-optional).

It's more than a shared folder:

- **It's the agent's knowledgebase**, once **Local AI** is enabled.
  [OpenViking](./ai/openviking) indexes everything in it every 15 minutes, and Hermes reaches that index as an MCP tool — so anything you put in the
  workspace is something the agent can find and cite, no upload step required.
- **A change to a file can start an automation.** The stack watches the whole workspace, so
  dropping a PDF in a folder or finishing a note runs whatever a handler in
  `.decree/handlers.yml` names for that path, whoever made the change. A handler fires once the
  file has been quiet for 30 seconds, so autosaves make one run. See
  [File Handlers](./decree/file-handlers).
- **You decide what does not fire.** A path a `.gitignore` in the workspace ignores, and
  anything in a `.git/`, never fires a handler. Beyond that the handlers decide: keep drafts
  out of a handler's folder until they're ready, and send an automation's output somewhere its
  own pattern doesn't reach.
- **`workspace/ai/`** is where agent output lands (`agent_task`'s answers, for instance). It's
  indexed like everything else, so an agent can build on a previous run's output.
- **`workspace/.decree/`** is your automations: the decree project the `automation` daemon
  runs. Machines, scripts, cron files and migrations written there run on the next tick, and
  `graph/` holds a Mermaid diagram of every machine, redrawn when one changes, readable in the
  editor's Markdown preview or Obsidian. The repo's own machines are copied in once and never
  again, so your edits win. Its
  `.gitignore` keeps run state local; secrets never live there. See
  [Writing a routine](./writing-a-routine).
- **`workspace/.capture/`** is everything you put in, as one stream — see
  [Capture](#capture).
- **`workspace/notes/you-were-here.md`** is the morning digest, and
  `notes/you-were-here/<YYYY>/` keeps one per day, with the [look backs](#look-back) beside them
  — see [You were here](#you-were-here).
- **Excluding your own files** is the desktop client's job: its *Ignored Files* list keeps
  anything you name off the server.

### Capture

What you asked an agent is the best record of what you were trying to do, so it is kept.
`workspace/.capture/` holds one JSON line per thing you typed — `ts`, `source`, `context` (the
directory, where known), `session` (the agent's session id, where it has one) and `text` —
in one file per writer and month (`2026-10-code-server.jsonl`), so two machines syncing the
workspace never edit the same file.
It syncs like the rest of the workspace.

Only what you typed is captured: never an AI's response, tool output or a transcript. Before
anything is written, secrets of common shapes — API keys and tokens (Anthropic, OpenAI, GitHub,
AWS, Slack, Google, JWTs, `Bearer …`), `password=`/`token=`/`api_key:` style assignments and
private key blocks — are replaced by a marker naming the kind, such as
`[REDACTED:anthropic-key]`. Capture never blocks the prompt: the write happens after the hook
has returned, and a failure is silent to you and logged to `workspace/.capture/errors.log`. It
writes nothing outside `workspace/.capture/`. One script does all of it:
`automation/lib/capture/capture.sh` (bash and `jq`).

| Source | On | Off |
|---|---|---|
| Claude Code in [code-server](./services/code-server) | By default: a `UserPromptSubmit` hook | `CODE_SERVER_CAPTURE=false` in `services/code-server/.env`, then `./existential.sh && docker compose up -d code-server` (turns off opencode too) |
| opencode in code-server | By default: a plugin, `automation/lib/capture/opencode.ts` | The same key |
| Claude Code on another machine (a laptop, the host) | `bash automation/lib/capture/capture.sh install <workspace dir>` from a checkout of this repo, with the workspace synced there | `bash automation/lib/capture/capture.sh uninstall` |
| Anything that can POST: a phone shortcut, an ntfy action, a voice memo transcript | `POST /capture` on `automation-webhook` (below), with the **Capture** add-on (`EXIST_IS_SERVICES_AUTOMATION_WEBHOOK=true`) | Delete the `/capture` entry from `workspace/.decree/decree-go-rest.yml` |

`install` adds the hook to `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR`'s), beside
whatever hooks you already have; `uninstall` removes only that one.

```bash
curl -X POST https://automation-webhook.<domain>/capture \
  -H "Authorization: Bearer $AUTOMATION_WEBHOOK_SECRET" \
  --data-binary '{"source":"phone","text":"buy filters"}'
```

The body is `{"source", "text"}` JSON (plus an optional `context`), or plain text, which is
filed with source `webhook`. The secret is `AUTOMATION_WEBHOOK_SECRET` in
`services/automation-webhook/.env`. Without the webhook, the same machine runs from
code-server's terminal: `cd /workspace && echo 'buy filters' | decree emit --machine capture`. An install from before capture existed keeps its own
`workspace/.decree/decree-go-rest.yml`; copy the `/capture` entry from
`automation/decree-go-rest.yml` into it.

### You were here

On a foggy day the hard part is remembering where you were. Every morning at 7 the
`you_were_here` machine writes `workspace/notes/you-were-here.md` and pushes the top of it to
ntfy:

- **The picture**: two or three sentences.
- **Waiting on you**: at most three, from `.decree/attention/` and runs waiting on a person.
- **One next thing.**
- **Holding steady**: machines whose last run succeeded, and the active schedules.
- **Where you left off**: what you were asking agents about, by project, with the last
  prompt of each session, from [the capture stream](#capture).
- **From your feeds**: only when `workspace/notes/feeds.md` exists. The feed URLs in it are
  read with the same RSS reader as the newsletter, and the three to five new items closest to
  what you were working on are shown, each once, ever.
- **Everything else** (the note only): decisions in `workspace/notes/decisions/`, captured
  prompts that read like a decision (listed as candidates, never as decided), notes touched
  with their open checkboxes, what is scheduled, and what changed since the last digest.

Every section is built from files except The picture, One next thing and the feed reasons. The
chat model writes those from the gathered facts, through `automation/lib/model.sh`, linking
each claim to its source; when it is unreachable the digest goes out without them. The push is
The picture, Waiting on you, One next thing and Holding steady, cut at a section boundary to
fit ntfy's 4096 bytes, and is skipped when nothing changed since the last digest. "Recent"
means since the last digest, or, when nothing new came in since, the window of the last one
that showed something, so a few quiet days never empty it.

Each day is also kept as `workspace/notes/you-were-here/<YYYY>/<YYYY-MM-DD>.md` (the last
digest of that day), with a **Done** section: checkboxes ticked, machines and migrations that
landed, runs that finished, notes created and what you worked on. A past day's file is never
touched again. No streaks and no "you missed N days". The **Worked on** lines name the capture
sources they came from, which is what a [work look back](#look-back) filters on.

The cron is active by default (`workspace/.decree/cron/you-were-here.md`, from
`automation-examples/cron/you-were-here.md`); edit its time there, or set its cron to
`0 0 31 2 *` to turn it off. `POST /you-were-here` on `automation-webhook` (the Capture add-on),
or `echo | decree emit --machine you_were_here` in code-server's terminal, writes one now, and
the machine's `note_link` param sets the push's last line, such as a URL to the note.
An install from before this keeps its own `workspace/.decree/decree-go-rest.yml`; copy the
`/you-were-here` entry from `automation/decree-go-rest.yml` into it.

### Look back

"What did I even do this year?" The `look_back` machine reads a range of the day notes above
and writes `workspace/notes/you-were-here/<YYYY>/look-back-<from>-<to>.md`, then sends a short
ntfy pointing at it:

- **Highlights**: checkboxes ticked, notes created and migrations landed, grouped by project
  (the capture context's folder, or the folder under `notes/`).
- **Themes**: the projects that came up on more than one day.
- **Decisions made**: notes in `notes/decisions/` and machines that landed.
- **By the numbers**: days recorded, prompts, checkboxes, notes, migrations, machines,
  decisions and runs. Counts only.

Every item links to the day note it came from. Only the archive is read, never rewritten. The
chat model writes an **In short** paragraph from those facts, linking each claim to its day;
when it is unreachable the look back is the data sections alone.

The default range is the year to date. `period` (`week`, `month`, `quarter` or `year`) is the
period up to `to` (today when blank), and `from`/`to` (`YYYY-MM-DD`) set either end:

```bash
docker exec automation decree emit --machine look_back --param period=quarter --param to=2026-09-30 </dev/null
```

With the Capture add-on, `POST /look-back` on `automation-webhook` does the year so far,
`/look-back/month` a period, `/look-back/month/work` a period at work only. From code-server's
terminal it is the same command as above, run in `/workspace` without `docker exec automation`.

**Work only**: `scope=work` keeps what `workspace/notes/you-were-here/scope.md` names: projects,
workspace folders (`notes/work/`) and capture sources (`claude-code`), one `- ` line each under
its heading. The file is written, empty, the first time a look back runs. A work look back is
`look-back-<from>-<to>-work.md`, so it never replaces the full one.

Every Sunday evening a weekly look back, and on a month's last evening a monthly one, are written
next to the day notes (`workspace/.decree/cron/look-back-weekly.md` and `look-back-monthly.md`,
on by default). A longer look back reads those for every whole week or month it covers, and day
notes only for the rest, so a year is about twelve files, not 365. An install from before this
copies the `/look-back` entries from `automation/decree-go-rest.yml` into its
`workspace/.decree/decree-go-rest.yml`.

### Syncing with a Nextcloud (optional)

Sync is optional: leave its keys blank and nothing syncs, and nothing else in the stack
notices. Set them, and `automation-backup` keeps `workspace/` in sync with a folder in a
Nextcloud, usually one on another server: its `workspace-sync` cron runs an `rclone bisync`
every five minutes, both ways. The keys are `EXIST_NEXTCLOUD_DOMAIN`, `EXIST_NEXTCLOUD_USER` and
`EXIST_NEXTCLOUD_APP_PASSWORD` (an app password from Nextcloud's *Settings → Security*) in
`.env`, all three; the folder is `EXIST_NEXTCLOUD_WORKSPACE_DIR`, `workspace` by default. The
credentials stay in `.env`, never under `workspace/`.

- **What never syncs:** anything a `.gitignore` under `workspace/` ignores, and every `.git/`.
  That is how decree's run state stays local, and how you keep any output local: ignore it.
- **Scripts stay runnable.** WebDAV drops file modes, so every sync marks
  `workspace/.decree/scripts/` executable again.
- **A mass delete waits for you.** A sync that would delete over half the files on one side
  deletes nothing, notifies you, and holds every later sync until you answer
  `docker exec automation-backup decree event <wait id> delete` (or `keep`, which copies each
  missing file back). `decree status` in `automation-backup` shows the wait.

With Nextcloud in this stack, the same keys work: the sync talks to the `nextcloud` container
directly. Its `workspace` folder is already this tree, so point `EXIST_NEXTCLOUD_WORKSPACE_DIR`
at another folder if you want a second copy.

### Bringing in real notes (e.g. an Obsidian vault)

Two different mechanisms, for two different jobs:

- [Obsidian](./services/obsidian) already documents syncing a vault through **Nextcloud**, for
  reading and editing it on your other devices. That's about *your* access to the vault.
- The simplest way to make it part of the agent's knowledgebase is to keep the vault *inside*
  the synced `workspace` folder. If it has to live somewhere else, pull it into
  `workspace/notes/` instead: copy `services/automation/backup/cron.example/notes-pull.md` to
  `services/automation/backup/cron/`, set `NOTES_PULL_SOURCE` to an `rsync`-over-SSH path (e.g.
  `user@nas:/path/to/vault/`), and drop a matching SSH key at
  `automation/secrets/notes-pull/id_ed25519`. It's opt-in and off by default (it needs your real
  source), pulls are additive by default (nothing is deleted locally unless you set
  `NOTES_PULL_DELETE=true`), and once it lands in `workspace/notes/` — an ordinary subdirectory —
  it is indexed and synced like everything else — though, being written to disk, it fires no
  events of its own.

## Integrations

Some services require additional OAuth or configuration steps:

```bash
./existential.sh run automation gmail-sync   # Gmail OAuth
./existential.sh run rclone                  # Remote file storage
```

See [Integrations](./integrations/) for setup details. For the full command list, run `./existential.sh run` with no arguments — it prints every available action.
