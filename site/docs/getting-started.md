---
sidebar_position: 2
---

# Getting Started

## Prerequisites

- [Docker](https://www.docker.com/get-started/), usable without sudo
  (`sudo usermod -aG docker "$USER"`, then log out and back in) — `existential.sh` refuses to run under sudo
- [Tailscale](https://tailscale.com/download), logged in on this machine and on every
  device that should reach the stack
- A machine to host the services (see [Hosting](./hosting/))
- Git clone the repo
  ```
  git clone https://github.com/jtmckay/existential.git
  cd existential
  ```

## Setup

```bash
./existential.sh quest
```

On a first run this asks two hardware questions and then offers **Core** — the whole system
wired together, rather than forty checkboxes. Say yes and you get a work dir you open in a
browser, a terminal there to talk to an AI, and decree to automate it, plus notifications and
monitoring. No GPU, no model downloads:

| | |
|---|---|
| **Network access** | Caddy (TLS + hostnames), Dashy (the dashboard) |
| **Workspace** | code-server (editor + terminal over the work dir) |
| **Automation** | Decree (and its webhook), ntfy (where automations report in) |
| **Observability** | Loki, Prometheus, Grafana (Decree's run logs and dashboards), Uptime Kuma |
| **Apps** | Actual Budget |

Files (Nextcloud), the house (Home Assistant), DNS (piHole) and GPU models usually run on other
servers, so Core leaves them out; each is an unnumbered quest (**Nextcloud**, **Voice & Home**,
**Local AI**).

Decline and you fall through to the full picker, then the quest list. The numbered quests there
are those same five rows one at a time — Core, taken apart — so you can build up to the same
stack in pieces and see every step instead of having it done for you. They cross themselves off
as you finish them, and running Core crosses off every one that can be checked from disk.
Everything unnumbered is an integration or automation past Core.

Either way, `./existential.sh` on its own does the same work without the questions:

1. Renders every `*.exist.*` template into its live counterpart, prompting for `EXIST_CLI` values
   and generating passwords and keys for the rest
2. Runs each enabled service's `exist.initial.sh` (pre-startup setup — certs, caches, seed config)
3. Generates a unified `docker-compose.yml` from all enabled services
4. Generates a master `.env` by merging `.env.shared` with every enabled service's `.env`

It also fills in `EXIST_LOCAL_HOST_IP` from `tailscale ip -4` (falling back to your LAN address
if tailscale isn't running) and derives `EXIST_DOMAIN` as `<that-ip-with-dashes>.nip.io`. nip.io
is public wildcard DNS, so every `https://<slug>.<domain>` resolves on any device with nothing
configured — while the tailnet address means only your own devices can route to it. No DNS
server, no router changes, no ports open to the internet.

:::warning
Don't set `EXIST_DOMAIN` to a MagicDNS name like `my-box.tailnet.ts.net`. MagicDNS resolves that
exact node name and nothing beneath it, so every `<slug>.` under it fails to resolve. Use the
tailnet **IP** in nip.io form — tailscale carries the traffic, nip.io supplies the wildcard.
:::

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

The workspace is *your* directory, `workspace/`: `notes/` for your notes (an Obsidian vault)
and `.decree/` for your automations. It lives in `volumes/workspace_data`. In Core,
[code-server](./services/code-server) opens it at `/workspace`, with an editor and a terminal
where `claude` and `opencode` are ready, and the `automation` daemon runs what is in its
`.decree/`. Add-ons mount the same tree: [Nextcloud](./storage/nextcloud) serves it as its
**`workspace`** folder and [Hermes](./ai/hermes) at `/opt/data/workspace`. Put notes, plans,
reference material — anything you want an agent to know about — there. Use it.

To edit it on your own machines, sync it: with Nextcloud in the stack, the **Nextcloud desktop
client** (nextcloud.com/install) logs in at `https://nextcloud.<domain>` and syncs the
`workspace` folder; with a Nextcloud elsewhere, see
[below](#nextcloud-on-another-server).

It's more than a shared folder:

- **It's the agent's knowledgebase**, once **Local AI** is enabled.
  [OpenViking](./ai/openviking) indexes everything in it every 15 minutes, and Hermes reaches that index as an MCP tool — so anything you put in the
  workspace is something the agent can find and cite, no upload step required.
- **Saving a file fires a webhook event**, with Nextcloud in the stack. Every upload through it is a file event
  Decree can react to — that's how the Workspace Agent quest (`./existential.sh quest`, or
  `src/quests/workspace-agent.md`) turns "you edited a note" into "an agent went and did
  something about it." See
  [File Processor](./decree/file-change-processing#triggering-on-workspace-edits).
- **What the stack writes does not fire.** Hermes, code-server and Decree write straight to
  disk. Nextcloud picks those files up within a minute, so they reach your devices, but they
  raise no event — which is what stops an agent's own answer from triggering another run.
- **`workspace/ai/`** is where agent output lands (`agent_task`'s answers, for instance). It's
  indexed like everything else, so an agent can build on a previous run's output.
- **`workspace/.decree/`** is your automations: the decree project the `automation` daemon
  runs. Machines, scripts, cron files and migrations written there run on the next tick, and
  `graph/` holds a Mermaid diagram of every machine, redrawn when one changes, so Obsidian shows
  them. The repo's own machines are copied in once and never again, so your edits win. Its
  `.gitignore` keeps run state local; secrets never live there. See
  [Writing a routine](./writing-a-routine).
- **`workspace/.capture/`** is everything you put in, as one stream — see
  [Capture](#capture).
- **Excluding your own files** is the desktop client's job: its *Ignored Files* list keeps
  anything you name off the server.

### Capture

What you asked an agent is the best record of what you were trying to do, so it is kept.
`workspace/.capture/` holds one JSON line per thing you typed — `ts`, `source`, `context` (the
directory, where known) and `text` — in one file per writer and month
(`2026-10-code-server.jsonl`), so two machines syncing the workspace never edit the same file.
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
| Anything that can POST: a phone shortcut, an ntfy action, a voice memo transcript | `POST /capture` on `automation-webhook` (below) | Delete the `/capture` entry from `workspace/.decree/decree-go-rest.yml` |

`install` adds the hook to `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR`'s), beside
whatever hooks you already have; `uninstall` removes only that one.

```bash
curl -X POST https://automation-webhook.<domain>/capture \
  -H "Authorization: Bearer $AUTOMATION_WEBHOOK_SECRET" \
  --data-binary '{"source":"phone","text":"buy filters"}'
```

The body is `{"source", "text"}` JSON (plus an optional `context`), or plain text, which is
filed with source `webhook`. The secret is `AUTOMATION_WEBHOOK_SECRET` in
`services/automation/.env`. An install from before capture existed keeps its own
`workspace/.decree/decree-go-rest.yml`; copy the `/capture` entry from
`automation/decree-go-rest.yml` into it.

### Nextcloud on another server

When Nextcloud runs elsewhere, `automation-backup` keeps `workspace/` in sync with a folder
there: its `workspace-sync` cron runs an `rclone bisync` every five minutes, both ways. Set
`EXIST_NEXTCLOUD_DOMAIN`, `EXIST_NEXTCLOUD_USER` and `EXIST_NEXTCLOUD_APP_PASSWORD` (an app
password from Nextcloud's *Settings → Security*) in `.env`; the folder is
`EXIST_NEXTCLOUD_WORKSPACE_DIR`, `workspace` by default. Until all three are set the cron does
nothing. The credentials stay in `.env`, never under `workspace/`.

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
