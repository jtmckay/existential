---
sidebar_position: 3
---

# The Pieces

:::info[Level 2 of 4 · Containers]
What is actually running, and how the parts fit together. Back out to
[Level 1 · What It Is](./intro), or zoom in to [Level 3 · Flows](./flows/) to follow one job
end to end.
:::

This is where the real names appear. Everything on this page is a replaceable choice — the
*shape* is the stable part, the projects filling each slot are not.

## The map

```mermaid
flowchart TB
    you["<b>You</b><br/><i>browser · phone</i>"]

    subgraph core["Core"]
        ts["Tailscale (host)<br/><i>real HTTPS on every device you log in</i>"]
        cs["code-server<br/><i>editor + terminal · claude · opencode</i>"]
        ws["<b>workspace/</b><br/><i>notes/ · .decree/</i>"]
        dec["decree<br/><i>runs workspace/.decree, nobody present</i>"]
        ntfy["ntfy<br/><i>tells you it finished</i>"]
    end

    model["A model at an OpenAI-compatible /v1 URL<br/><i>ollama · llama.cpp · another box</i>"]

    subgraph addons["Optional add-ons"]
        ai["Local AI<br/><i>Ollama · Hermes · OpenViking · Honcho · Firecrawl</i>"]
        voice["Voice &amp; Home<br/><i>Home Assistant · wyoming-whisper · wyoming-piper</i>"]
        files["Capture<br/><i>automation-webhook · Nextcloud syncs workspace/</i>"]
        more["Network · Monitoring · Apps<br/><i>Caddy · Dashy · Grafana · Actual Budget · …</i>"]
    end

    you --> ts
    ts --> cs
    ts --> ntfy
    cs <--> ws
    dec <--> ws
    dec --> ntfy
    cs -. opencode .-> model
    dec -. model.sh .-> model
    ai -. serves .-> model
    files <-. sync .-> ws

    classDef me fill:#e8f4fd,stroke:#027bcb,stroke-width:2px,color:#111
    classDef hub fill:#027bcb,stroke:#014d80,stroke-width:2px,color:#fff
    classDef box fill:#f4f4f4,stroke:#999,color:#333
    classDef ext fill:#fff,stroke:#666,stroke-dasharray:4 3,color:#333
    class you me
    class ws hub
    class ts,cs,dec,ntfy box
    class model,ai,voice,files,more ext
    style core fill:#fcfcfc,stroke:#027bcb,stroke-width:2px,color:#014d80
    style addons fill:#fff,stroke:#999,stroke-dasharray:4 3,color:#333
```

### Reading that in three lines

1. **You work in one folder.** `workspace/` holds `notes/` (plain markdown), `.decree/`
   (your automations) and `.capture/` (your agent prompts and anything else you capture — see
   [Capture](./getting-started#capture)). code-server opens it in a browser, with `claude`
   and `opencode` in the terminal, and `claude` started there already knows how to write a
   decree machine; [Nextcloud](./storage/nextcloud), if you add it, syncs it to your other devices.
2. **decree is the hands.** It runs the machines in `workspace/.decree/` on a schedule or an
   inbox message (or a webhook, with the Capture add-on), against your apps and your data, and tells you through ntfy.
   Every morning it writes a [you were here](./getting-started#you-were-here) digest of what
   needs you, what is holding steady and where you left off, and every Sunday and month-end a
   [look back](./getting-started#look-back) over them.
   With the Monitoring add-on, every run log lands in Loki.
3. **A model is a URL.** Anything that needs one, a decree script or opencode, reaches it at an
   OpenAI-compatible `/v1` address. Ollama on this box, llama.cpp on
   [another one](./hosting/ai-box), anything that serves `/v1`: nothing else changes.

The platform is free to every service: a place to put data comes with the folder, and with the
Network and Monitoring add-ons so do a name, a certificate and somewhere its logs go. A service
doesn't opt in.

## The AI, slot by slot

None of this is in Core. Core needs only a model URL, and only for the automations that ask a
model something; the **Local AI** quest adds the first five rows, **Voice & Home** the next ones.

| Slot | Ships as | Why it's separate |
|---|---|---|
| **Models** | [Ollama](./ai/ollama), or any OpenAI-compatible server | Loads and serves the weights at `EXIST_MODEL_URL`. Each role (chat, extract, embed, vision) can point somewhere else — see [Configuration](./configuration#endpoints--putting-roles-on-different-machines). |
| **Agent** | [Hermes](./ai/hermes) | An agent with tools, skills and sessions, over that same model URL. Optional: decree reaches a model without it, and uses it only for work that needs an agent. |
| **Knowledge** | [OpenViking](./ai/openviking) | A `viking://` context database holding memory, resources and skills, so the agent has somewhere durable to keep what it knows rather than re-deriving it each session. |
| **Memory** | [Honcho](./ai/honcho) | Cross-session memory about *you*. Without it every conversation starts cold; with it, what it learned last week is still there. |
| **The web** | [Firecrawl](./ai/firecrawl) | Turns a URL into clean markdown a model can read, so no surface or routine has to carry its own browser automation. |
| **Speech → text (voice)** | [wyoming-whisper](./ai/wyoming-whisper) | What Home Assistant listens with. Speaks the Wyoming protocol HA expects, and runs on CPU so it never evicts the model from the GPU. |
| **Text → speech (voice)** | [wyoming-piper](./ai/wyoming-piper) | The voice it answers in, over the same protocol and also on CPU — a spoken reply has to land immediately. |
| **Voice front end** | [Home Assistant](./services/homeassistant) | Wake word, microphones, speakers, and the ability to actually *do* something in the house. |
| **Speech → text (recordings)** | [WhisperX](./ai/whisperx) | A different job: long recordings with speaker labels, on the GPU, driven by decree rather than by HA. |
| **Text → speech (HTTP)** | [Chatterbox](./ai/chatterbox) | Optional, and off by default: expressive and cloneable over an OpenAI-compatible API, for audio generated outside the HA pipeline. No quest enables it and nothing in the stack calls it yet — it is here for you to build against. |
| **Chat front end** | [Open WebUI](./ai/open-web-ui) | Day-to-day conversation in a browser. Opt-in: Hermes also answers by voice, from code-server's terminal (`hermes "..."`), and from automations. |

The reason for one URL is the whole thesis in miniature: **figure the model out once, and
everything that needs one inherits it.** Swap what serves it and no caller notices.

:::caution[Editing the stack is not one of the surfaces]
Hermes is not a coding backend for this repo — it is an agent running its own tool loop, and
opencode's streaming parser rejects its tool-progress frames
([why](./decree/routing#why-not-opencode)). Change the stack with a dedicated coding agent on
the host, against a frontier model. Hermes' agent work stays where it works: in a container, on
`workspace/` — see [agent_task](./decree/) and [code-server](./services/code-server).
:::

## How it's assembled

The whole system, in one sentence:

> **You set a true/false flag per service. Everything enabled gets rendered and merged into
> one compose file and one env file, and runs on one shared network.**

That's it. There is no plugin system, no service registry, no orchestrator. If you understand
those three steps you understand the entire stack.

### 1. Choose — a flag per service

Every service is a folder, and every folder gets one flag in `.env.shared`:

```bash
EXIST_IS_<CATEGORY>_<SLUG>=true|false
```

The name is derived from the path, not declared anywhere: `ai/firecrawl` →
`EXIST_IS_AI_FIRECRAWL`, `services/code-server` → `EXIST_IS_SERVICES_CODE_SERVER`. Categories
are the top-level folders — `ai/`, `services/`, `nas/`, `hosting/`.

Disabled services are skipped entirely. No templates render, no secrets are generated, nothing
lands on disk.

### 2. Render — templates become live files

`./existential.sh` walks every enabled service and renders its `*.exist.*` templates into real
files, generating secrets as it goes (`EXIST_32_CHAR_HEX_KEY` and friends).

```
docker-compose.exist.yml   →  docker-compose.yml
.env.exist                 →  .env
config.exist.yml           →  config.yml
```

Templates are tracked in git; rendered files never are.

**Rendering happens once per file.** If the destination already exists it is left alone, so
the passwords you were prompted for and the edits you made afterwards survive every
subsequent run. There is no flag to re-render over them — `./existential.sh reset` archives
the rendered files to `archive/<timestamp>/` and the next run renders fresh, so nothing is
overwritten without a copy you can restore.

Written-once is the right rule for a file, but the wrong one for a *key*. A setting added
upstream would otherwise never reach an install that had already rendered: the file exists, so
it is skipped, and the new value is silently empty everywhere that reads it. So `.env` files are
reconciled key by key on every run — anything the template has and your file lacks is appended,
with its comment, and named in the output. It is append-only: existing values are never changed,
blanks are never filled (blank is meaningful — it is how "not asked yet" is recorded), and
nothing is removed. That is what makes `git pull && ./existential.sh` an upgrade.

Two other exceptions cover config that would otherwise go stale:

**Files that hold nothing you could lose** — no secrets, no prompted answers — are
**regenerated on every run**, so a value like `EXIST_DOMAIN` baked into them can't go stale.
They carry a `DO NOT EDIT` header saying so. Dashy's `dashy-conf.yml` and Honcho's `config.toml`
are the two today. If you'd rather own one, flip `# EXIST_KEEP: false` to `true` in its header
and the file is yours from then on — never regenerated again.

**Config that lives inside a service's own datastore** can't be reached by any of the above: it
does not exist until that service's first boot, and the service rewrites it on shutdown. Those
are trued up by the service's own `entrypoint.sh`, in the moment between the container starting
and the service starting. Home Assistant's reverse-proxy settings, Nextcloud's trusted domains
and ntfy's publishing user all work this way — which is why changing `EXIST_DOMAIN` moves the
whole stack instead of half of it.

### 3. Merge — one compose file, one env file

Every enabled service's `docker-compose.yml` is merged into a single `docker-compose.yml` at
the repo root, and every service `.env` is merged into one master `.env` beside it. Relative
paths are rewritten so they resolve from the root.

```bash
docker compose up -d     # always from the repo root, never from a service folder
```

The generated root compose file is **always** overwritten — never edit it. Edit the service's
`docker-compose.exist.yml` and re-run `./existential.sh`.

## Adding a service is adding a folder

There is no list to register in. Create `<category>/<slug>/docker-compose.exist.yml`, add the
matching `EXIST_IS_*` flag, and it exists. The folder name *is* the service name — it becomes
the container prefix, the flag, and the hostname.

## One network

Everything enabled joins one Docker bridge network named `exist`, and reaches everything else
by container name:

```
http://ollama:11434     http://firecrawl:3002     http://automation-webhook:8801
```

No service discovery, no ports published to the host unless you ask. Browser access goes
through Caddy at `https://<slug>.<domain>`; container-to-container traffic uses the plain
hostname above — faster, and no TLS to trust.

## Hostnames that just work

`EXIST_DOMAIN` defaults to `<your-host-ip-with-dashes>.nip.io`, derived automatically on the
first run from this machine's LAN address:

```
EXIST_LOCAL_HOST_IP=192.168.1.20          (LAN address)
        ↓
EXIST_DOMAIN=192-168-1-20.nip.io   →  https://dashy.192-168-1-20.nip.io
```

[nip.io](https://nip.io) is public wildcard DNS: any name ending in `<ip>.nip.io` resolves
straight back to that IP. Nothing to register, nothing to configure. **Every device on your
network can reach the stack immediately — no pihole, no `/etc/hosts`, no DNS setup.**

The two halves do different jobs. **nip.io supplies the wildcard**, so a new service needs no
DNS change — ever. **Your network supplies the reachability**: the name is public, but a LAN
address only routes inside your house. No router config, no port forwarding, nothing exposed.
Reaching it from elsewhere is a VPN back to that network, any one you like — see
[VPN](./hosting/vpn.md).

If you use Tailscale and it is up, the first run prefers its `100.64.0.0/10` tailnet address
over the LAN one (`tailscale ip -4`), so the same names reach the stack from every device on
your tailnet, and from nowhere else.

:::danger If you use Tailscale, don't use a MagicDNS name

Setting `EXIST_DOMAIN=my-box.tailnet.ts.net` looks correct and fails. MagicDNS resolves that
**exact node name** and nothing beneath it — there is no wildcard under a node — so
`dashy.my-box.tailnet.ts.net` is NXDOMAIN and the whole `<slug>.<domain>` convention collapses.
Use the tailnet **IP** in nip.io form.

The same reasoning rules out `tailscale serve`: it terminates TLS for one hostname per node
with path-based routing, so it cannot give forty services forty hostnames.
:::

The catch: that lookup goes to the internet. If your WAN link is down, the names stop
resolving even on the host itself — which is what pihole fixes, below. And every lookup is a
query to nip.io's public DNS, so nip.io sees your host's IP and each service name you look up.
Local DNS (such as [pihole](./hosting/pihole.md)) or [a domain you own](#owned-domain-without-exposing-your-network)
avoids that.

### Upgrading an existing install

Services now derive their hostname from `EXIST_DOMAIN` at container start
(`${CADDY_DOMAIN:-$EXIST_DOMAIN}`) rather than having it baked in when the template was
rendered, so changing `EXIST_DOMAIN` propagates on the next `docker compose up -d`.

That only applies to a *fresh* render. Rendered `.env` files are yours — the setup script
never overwrites them — so an install from before this change still carries the old baked
values, and they win over the new defaults. To pick up the change, delete these lines from
your rendered `.env` files if present:

| File | Delete |
|---|---|
| `hosting/caddy/.env` | `CADDY_DOMAIN=` |
| `services/mealie/.env` | `MEALIE_BASE_URL=` |
| `nas/collabora/.env` | `COLLABORA_DOMAIN=`, `COLLABORA_NEXTCLOUD_DOMAIN=` |

Set them again only if you deliberately want that service on a different domain from the
rest of the stack.

Rendered non-`.env` files are skipped the same way. If `hosting/caddy/Caddyfile` predates a
service you now have enabled, it has no site block for it — copy the missing block across
from `Caddyfile.exist.Caddyfile` by hand, or run `./existential.sh reset` to archive every
rendered file and render the lot fresh. Reset also archives Decree's own runtime state —
`volumes/workspace_data/.decree/runs/` (every run's logs) and `volumes/workspace_data/.decree/processed.md` (the migration ledger) —
so a fresh render starts with a clean history too, not just clean config. Reset lists exactly
what it will move and asks first, and beyond that decree state it never touches your `_data` or
`_backup` volumes — it only offers to delete the `*_cache` ones, which the stack refetches on the next start.

If a command instead complains about permissions — `rm: Permission denied` during setup, or a
reset that can't write `archive/` — some path in the repo is owned by root. Docker does this: a
bind mount whose host directory doesn't exist yet gets created by the daemon, and the daemon runs
as root. `./existential.sh` creates every volume directory your enabled services need, correctly
owned, so this mostly happens only if you run `docker compose up -d` in a tree that was never
rendered. `./existential.sh run fix-permissions` gives those paths back to you (add `--dry-run` to
see the list first). It never deletes anything, and it borrows root from a throwaway container
rather than asking you for `sudo`.

### Two independent choices, not one upgrade path

There are two separate questions, and you can answer them in either order. Nothing forces
you to change both.

1. **How do names resolve?** → public DNS, or pihole
2. **Does the browser trust the cert?** → the stack's own CA, or a real certificate

|                    | **Internal CA** (trust once per device) | **Real certificate** (nothing to trust) |
|---|---|---|
| **nip.io** *(default)* | Zero setup. Needs internet for DNS. | Not possible — you don't control the `nip.io` zone. |
| **pihole** | Fully offline. Resolves locally. | **Fully offline *and* no warnings.** See below. |

Neither question is about *reachability* — that is your network's (or your VPN's) job, and it
is orthogonal to both. You can move along either axis without touching it.


The bottom-right cell is the good one, and it needs a domain you own — but **not** a public
A record, and **not** any inbound connectivity.

**Adding pihole is an upgrade, not a requirement.** Its single wildcard record answers the
same names locally, which removes the internet-DNS dependency. Nothing else changes, and
container-to-container traffic was never affected either way.

## Owned domain without exposing your network

The usual objection to a real certificate is that it means opening your network up. It
doesn't. **The DNS-01 challenge never requires an inbound connection.**

Let's Encrypt proves you own a domain by reading a `TXT` record from *public* DNS. Your
machine makes an **outbound** call to your DNS provider to create that record. Let's Encrypt
reads it from the DNS system — it never connects to you.

```
your host  ──outbound──▶  DNS provider API   (creates _acme-challenge TXT)
Let's Encrypt  ──reads──▶  public DNS         (never touches your network)

meanwhile:
pihole  ──▶  local.example.com  =  192.168.1.50   (resolution stays entirely on your LAN)
```

So you can have all of this at once:

- a **real, trusted certificate** — no warnings on any device, including phones
- **no public A record** — your LAN IP is never published
- **no port forwarding**, no inbound exposure of any kind
- **local DNS** via pihole, so name resolution works with the WAN unplugged

The only internet the setup needs is an outbound DNS API call at renewal time, roughly every
60 days.

### Setting it up

You need a domain and a DNS provider with an API. HTTP-01 will **not** work — it requires
Let's Encrypt to reach your server, which is exactly what you're avoiding.

**Option A — issue the cert elsewhere, drop it in.** Works with the stack as shipped:

```bash
# on any machine with internet, using your provider's DNS plugin
acme.sh --issue --dns dns_cf -d '*.local.example.com' -d local.example.com
```

Copy the result into `hosting/caddy/certs/` as `internal.pem` and `internal-key.pem`. Caddy's
`exist.initial.sh` skips minting whenever a leaf cert is already present, so it will use
yours untouched. Renew and re-copy every 90 days.

**Option B — let Caddy renew it automatically.** Caddy can do DNS-01 itself, but the stock
`caddy:2.11.4` image the stack ships contains **no DNS provider plugins** — you'd need a
custom image built with `xcaddy` including your provider's module, plus an API token in the
container. More moving parts, no manual renewals.

Then point `EXIST_DOMAIN` at your domain and add the pihole record:

```
EXIST_DOMAIN=local.example.com
address=/local.example.com/192.168.1.50     # pihole, resolves entirely on-LAN
```

:::note[Why not with nip.io or .internal]
`.internal` isn't a real domain, so no CA will ever issue for it. `nip.io` is real but not
yours — DNS-01 needs write access to the zone, and HTTP-01 needs a public IP. Either way the
internal CA is the only option there, which is why the default keeps it.
:::

## Core vs. complementary services

This is about the network, not the Core quest: the Monitoring add-on is complementary by this
test.

Not everything needs to be on that network. A service is **core** if it talks to other
services over the bridge. A service is **complementary** if it either talks over a normal URL
or protocol, or if nothing in the stack talks to it at all.

Complementary services can move to a different machine without changing how anything else
works. Today they still default to the `exist` network because it's simpler on one host — but
nothing about them depends on it.

| Service | Why it's complementary |
|---|---|
| **NAS** (Nextcloud, Collabora) | The core stack reaches these over **rclone remotes and their HTTP APIs** — a URL, not a container name. |
| **Immich** | Nothing in the stack talks to it. It's a photo library that happens to be self-hosted alongside. |
| **Home Assistant** | Nothing in the stack talks to it either. It usually wants to live on whichever machine has your Zigbee/Z-Wave dongles plugged in. |
| **pi-hole** | LAN DNS. It serves your whole network, not the stack. No service calls it. |
| **Monitoring** (Grafana, Loki, Prometheus, Uptime-Kuma) | Scrapes and receives; nothing depends on it to function. |

The tell is simple: **if the connection is a URL you could point anywhere, the service is
complementary.** If it's a bare container name, it's core.

## Recommended deployment

Even on a single machine, it's worth thinking of this as separate stacks. It costs nothing now
and means moving one of them later is a config change rather than a migration. Core is already
cut this way: it is the middle box, and the others are add-ons that usually live elsewhere.

```
┌─ NAS stack ──────────────┐   Storage and files.
│  Nextcloud, Collabora    │   Wants disks, not GPU.
│                          │   Reached over rclone / WebDAV URLs.
└──────────────────────────┘

┌─ Core stack ─────────────┐   The actual system.
│  code-server, decree,    │   Wants CPU and RAM, no GPU.
│  ntfy                    │   One network, container-name DNS.
└──────────────────────────┘

┌─ AI box ─────────────────┐   The models.
│  Ollama or llama.cpp,    │   Wants the GPU.
│  ComfyUI, …              │   Reached over an OpenAI-compatible /v1 URL.
└──────────────────────────┘

┌─ Standalone ─────────────┐   Independent appliances.
│  Immich      pi-hole     │   Own lifecycle, own machine if you like.
│  Home Assistant          │   HA follows your USB radios.
└──────────────────────────┘
```

**Why split the NAS.** Storage and compute want different hardware and different reboot
schedules. Adding disks shouldn't take the rest of the stack down. Because the core reaches
storage through rclone and WebDAV, moving the NAS to its own box means changing an endpoint —
not rewiring anything. `workspace/` then [stays in sync with
it](./getting-started#syncing-with-a-nextcloud-optional).

**Why split the models.** Restarting a model server to load a new model shouldn't interrupt
anything else, and the GPU is rarely in the same box as the disks. Every caller reaches a model
by URL, so the [AI box](./hosting/ai-box) is a value in `.env.shared`.

**Why pi-hole is separate.** It's your LAN's DNS server. It should stay up when you're
rebuilding the stack, which is exactly when you're most likely to break something.

**Why Home Assistant is separate.** It's usually pinned to physical hardware — a Zigbee or
Z-Wave stick in a USB port — so the machine it runs on is decided by where your radios are,
not by where your GPU is. It also runs your lights and locks, which you want working while
you rebuild everything else.

### Moving one to another machine

1. Set that service's `EXIST_IS_*` flag to `false` on the original host and re-run
   `./existential.sh`.
2. Bring the service up on the new host.
3. Update the endpoint that pointed at it — the rclone remote, the model URL, or the DNS record.

Nothing else changes. That is the entire point of the split.
