---
sidebar_position: 2
---

# Getting Started

## Prerequisites

- [Docker](https://www.docker.com/get-started/)
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
wired together, rather than forty checkboxes. Say yes and you get files, the house, the agent,
its memory and voice, plus notifications and monitoring:

| | |
|---|---|
| **Front door** | Caddy (TLS + hostnames), Dashy (the dashboard) |
| **Files** | Nextcloud, Redis, MinIO (S3 + file events) |
| **House** | Home Assistant |
| **Automation** | Decree, ntfy (where automations report in) |
| **Monitoring** | Loki, Prometheus, Grafana — Decree's run logs and dashboards |
| **Agent** | Ollama, Hermes, Open WebUI, Honcho (memory), OpenViking (context), Firecrawl |
| **Voice** | wyoming-whisper (speech to text), wyoming-piper (text to speech) |

Decline and you fall through to the full picker. Either way, `./existential.sh` on its own does
the same work without the questions:

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
full agent path: point `EXIST_OLLAMA_URL` at a box that has the VRAM.

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

## Workspace

`workspace/` at the repo root is *your* directory — the same tree [Hermes](./ai/hermes) mounts
at `/opt/data/workspace` and [code-server](./services/code-server) mounts at `/workspace`. Put
notes, plans, reference material — anything you want the agent to know about — there. Use it.

It's more than a shared folder:

- **It's the agent's knowledgebase.** [OpenViking](./ai/openviking) indexes everything in it
  every 15 minutes, and Hermes reaches that index as an MCP tool — so anything you put in
  `workspace/` is something the agent can find and cite, no upload step required.
- **It's synced both ways with MinIO/Nextcloud.** With MinIO and Nextcloud enabled (on by
  default with Core), `workspace/` bisyncs with the `workspace/` folder inside Nextcloud's `/S3`
  external storage — edit a file on this machine, in Nextcloud's web UI, or directly in MinIO,
  and the other two converge on it, usually within seconds. See
  [File Processor](./decree/file-change-processing#triggering-on-workspace-edits) for exactly
  how.
- **Syncing fires webhook events.** Every change that lands in the bucket is a MinIO event
  Decree can react to — that's how the Workspace Agent quest (`./existential.sh quest`, or
  `src/quests/auto-workspace-agent.md`) turns "you edited a note" into "an agent went and did
  something about it."
- **`workspace/ai/`** is where agent output lands (`agent-task`'s answers, for instance). It's
  indexed like everything else, so an agent can build on a previous run's output — but it's
  deliberately excluded from the MinIO sync, which is what stops an agent's own answer from
  triggering another run.
- **Excluding your own files:** drop a `.syncignore` at `workspace/.syncignore` — one glob
  pattern per line, same syntax as `.gitignore` — for anything you don't want leaving this
  machine.

### Bringing in real notes (e.g. an Obsidian vault)

Two different mechanisms, for two different jobs:

- [Obsidian](./services/obsidian) already documents syncing a vault through **Nextcloud**, for
  reading and editing it on your other devices. That's about *your* access to the vault.
- To make an existing vault part of the agent's knowledgebase, pull it into
  `workspace/notes/` instead: copy `services/automation/backup/cron.example/notes-pull.md` to
  `services/automation/backup/cron/`, set `NOTES_PULL_SOURCE` to an `rsync`-over-SSH path (e.g.
  `user@nas:/path/to/vault/`), and drop a matching SSH key at
  `automation/secrets/notes-pull/id_ed25519`. It's opt-in and off by default (it needs your real
  source), pulls are additive by default (nothing is deleted locally unless you set
  `NOTES_PULL_DELETE=true`), and once it lands in `workspace/notes/` — an ordinary subdirectory —
  everything above (indexing, sync, webhooks) already applies to it with no extra setup.

## Integrations

Some services require additional OAuth or configuration steps:

```bash
./existential.sh run automation gmail-sync   # Gmail OAuth
./existential.sh run rclone                  # Remote file storage
```

See [Integrations](./integrations/) for setup details. For the full command list, run `./existential.sh run` with no arguments — it prints every available action.
