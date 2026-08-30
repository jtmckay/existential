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
    ha["Home Assistant<br/><i>voice, in the house</i>"]
    owui["Open WebUI<br/><i>chat in a browser</i>"]
    oc["opencode<br/><i>editor and terminal</i>"]
    dec["decree<br/><i>routines, nobody present</i>"]

    hermes["<b>Hermes</b> — the one endpoint<br/><i>OpenAI-compatible · sessions · skills</i>"]
    ollama["Ollama<br/><i>the models</i>"]
    stt["WhisperX<br/><i>speech → text</i>"]
    tts["Chatterbox<br/><i>text → speech</i>"]

    viking["OpenViking<br/><i>what it knows</i>"]
    honcho["Honcho<br/><i>what it remembers about you</i>"]
    craw["Firecrawl<br/><i>reading the web</i>"]

    apps["Your apps<br/><i>notes · photos · money · files · recipes …</i>"]
    platform["<b>The platform</b> — free to every service<br/><i>Caddy names + TLS · volumes and NAS · logs and metrics</i>"]

    ha --> hermes
    owui --> hermes
    oc --> hermes
    dec --> hermes
    ha --> stt
    ha --> tts
    hermes --> ollama
    hermes --> viking
    hermes --> honcho
    hermes --> craw
    dec <--> apps
    hermes --> platform
    apps --> platform

    classDef surface fill:#e8f4fd,stroke:#027bcb,color:#111
    classDef gateway fill:#027bcb,stroke:#014d80,stroke-width:2px,color:#fff
    classDef model fill:#f4f4f4,stroke:#999,color:#333
    classDef base fill:#fff,stroke:#666,stroke-dasharray:4 3,color:#333
    classDef reach fill:#fdf6e8,stroke:#c98a1b,color:#333
    class ha,owui,oc,dec surface
    class hermes gateway
    class ollama,stt,tts,apps model
    class viking,honcho,craw reach
    class platform base
```

### Reading that in three lines

1. **Everything talks to Hermes.** Voice, browser, editor and automation all hit one
   OpenAI-compatible endpoint. Nothing else knows which model is loaded.
2. **decree is the hands.** It watches for things happening and runs routines against your
   apps and your data — calling Hermes when the work needs judgment.
3. **The platform is free to every service.** A name, a certificate, a place to put data and
   somewhere its logs go come with the folder; a service doesn't opt in.

## The AI spine, slot by slot

| Slot | Ships as | Why it's separate |
|---|---|---|
| **Gateway** | [Hermes](./ai/hermes) | One OpenAI-compatible URL and API key for every surface. Sessions, skills and memory live here, so they're shared rather than per-app. |
| **Models** | [Ollama](./ai/ollama) | Loads and serves the weights. Swapping model is a config change behind the gateway; no surface notices. |
| **Knowledge** | [OpenViking](./ai/openviking) | A `viking://` context database holding memory, resources and skills, so the agent has somewhere durable to keep what it knows rather than re-deriving it each session. |
| **Memory** | [Honcho](./ai/honcho) | Cross-session memory about *you*. Without it every conversation starts cold; with it, what it learned last week is still there. |
| **The web** | [Firecrawl](./ai/firecrawl) | Turns a URL into clean markdown a model can read, so no surface or routine has to carry its own browser automation. |
| **Speech → text (voice)** | [wyoming-whisper](./ai/wyoming-whisper) | What Home Assistant listens with. Speaks the Wyoming protocol HA expects, and runs on CPU so it never evicts the model from the GPU. |
| **Text → speech (voice)** | [wyoming-piper](./ai/wyoming-piper) | The voice it answers in, over the same protocol and also on CPU — a spoken reply has to land immediately. |
| **Speech → text (recordings)** | [WhisperX](./ai/whisperx) | A different job: long recordings with speaker labels, on the GPU, driven by decree rather than by HA. |
| **Text → speech (HTTP)** | [Chatterbox](./ai/chatterbox) | Expressive and cloneable, over an OpenAI-compatible API — for anything in the stack generating audio outside the HA pipeline. |
| **Voice front end** | [Home Assistant](./services/homeassistant) | Wake word, microphones, speakers, and the ability to actually *do* something in the house. |
| **Chat front end** | [Open WebUI](./ai/open-web-ui) | Day-to-day conversation, pointed at Hermes rather than at a model. |
| **Coding front end** | [opencode](./ai/ollama#opencode-integration) | Configured with the Hermes URL as its OpenAI endpoint, so it shares the same models and skills. |
| **No-human surface** | [decree](./decree/) | The automation engine. Routines call the gateway exactly like you would. |

The reason for the gateway is the whole thesis in miniature: **figure the model, the key, the
skills and the memory out once, and four surfaces inherit it.** Without it you would configure
each one separately and they would drift.

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

The exception is files that hold nothing you could lose — no secrets, no prompted answers.
Those are **regenerated on every run** so a value like `EXIST_DOMAIN` baked into them can't
go stale, and they carry a `DO NOT EDIT` header saying so. Dashy's `dashy-conf.yml` is the
one today: it bakes the domain because Dashy reads a static config file, and it re-renders
every run so changing your domain updates it along with everything else. If you'd rather
own it, flip `# EXIST_KEEP: false` to `true` in its header and the file is yours from then
on — never regenerated again.

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
http://ollama:11434     http://firecrawl:3002     http://decree-webhook:8801
```

No service discovery, no ports published to the host unless you ask. Browser access goes
through Caddy at `https://<slug>.<domain>`; container-to-container traffic uses the plain
hostname above — faster, and no TLS to trust.

## Hostnames that just work

`EXIST_DOMAIN` defaults to `<your-host-ip-with-dashes>.nip.io`, derived automatically on the
first run. The IP comes from `tailscale ip -4`, falling back to your LAN address if tailscale
isn't running:

```
EXIST_LOCAL_HOST_IP=100.101.102.103          (tailnet address)
        ↓
EXIST_DOMAIN=100-101-102-103.nip.io   →  https://dashy.100-101-102-103.nip.io
```

[nip.io](https://nip.io) is public wildcard DNS: any name ending in `<ip>.nip.io` resolves
straight back to that IP. Nothing to register, nothing to configure. **Every device you own
can reach the stack immediately — no pihole, no `/etc/hosts`, no DNS setup.**

The two halves do different jobs. **nip.io supplies the wildcard**, so a new service needs no
DNS change — ever. **Tailscale supplies the reachability**, and because a `100.64.0.0/10`
address only routes inside your tailnet, the name is public but the stack is not: your laptop
reaches it from a hotel, and nobody else reaches it at all. No router config, no port
forwarding, nothing exposed.

:::danger Don't use a MagicDNS name
Setting `EXIST_DOMAIN=my-box.tailnet.ts.net` looks correct and fails. MagicDNS resolves that
**exact node name** and nothing beneath it — there is no wildcard under a node — so
`dashy.my-box.tailnet.ts.net` is NXDOMAIN and the whole `<slug>.<domain>` convention collapses.
Use the tailnet **IP** in nip.io form.

The same reasoning rules out `tailscale serve`: it terminates TLS for one hostname per node
with path-based routing, so it cannot give forty services forty hostnames.
:::

The catch: that lookup goes to the internet. If your WAN link is down, the names stop
resolving even on the host itself — which is what pihole fixes, below.

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
rendered file and render the lot fresh. Reset lists exactly what it will move and asks
first, and it never touches your `_data` or `_backup` volumes — it only offers to delete the
`*_cache` ones, which the stack refetches on the next start.

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

Neither question is about *reachability* — that is tailscale's job, and it is orthogonal to
both. You can move along either axis without touching your tailnet.

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

Not everything needs to be on that network. A service is **core** if it talks to other
services over the bridge. A service is **complementary** if it either talks over a normal URL
or protocol, or if nothing in the stack talks to it at all.

Complementary services can move to a different machine without changing how anything else
works. Today they still default to the `exist` network because it's simpler on one host — but
nothing about them depends on it.

| Service | Why it's complementary |
|---|---|
| **NAS** (Nextcloud, MinIO, Collabora, Redis) | The core stack reaches these over **rclone remotes and the S3 API** — a URL, not a container name. `redis` is used only by Nextcloud, inside the NAS group. |
| **Immich** | Nothing in the stack talks to it. It's a photo library that happens to be self-hosted alongside. |
| **Home Assistant** | Nothing in the stack talks to it either. It usually wants to live on whichever machine has your Zigbee/Z-Wave dongles plugged in. |
| **pi-hole** | LAN DNS. It serves your whole network, not the stack. No service calls it. |
| **Monitoring** (Grafana, Loki, Prometheus, Uptime-Kuma) | Scrapes and receives; nothing depends on it to function. |

The tell is simple: **if the connection is a URL you could point anywhere, the service is
complementary.** If it's a bare container name, it's core.

## Recommended deployment

Even on a single machine, it's worth thinking of this as three separate stacks. It costs
nothing now and means moving one of them later is a config change rather than a migration.

```
┌─ NAS stack ──────────────┐   Storage and files.
│  Nextcloud, MinIO,       │   Wants disks, not GPU.
│  Collabora, Redis        │   Reached over rclone / S3 URLs.
└──────────────────────────┘

┌─ Core stack ─────────────┐   The actual system.
│  decree, Hermes, Ollama, │   Wants CPU/GPU and RAM.
│  Caddy, OpenViking, …    │   One network, container-name DNS.
└──────────────────────────┘

┌─ Standalone ─────────────┐   Independent appliances.
│  Immich      pi-hole     │   Own lifecycle, own machine if you like.
│  Home Assistant          │   HA follows your USB radios.
└──────────────────────────┘
```

**Why split the NAS.** Storage and compute want different hardware and different reboot
schedules. Restarting Ollama to load a new model shouldn't interrupt file sync, and adding
disks shouldn't take the AI stack down. Because the core reaches storage through rclone and
S3, moving the NAS to its own box means changing an endpoint — not rewiring anything.

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
3. Update the endpoint that pointed at it — the rclone remote, the S3 URL, or the DNS record.

Nothing else changes. That is the entire point of the split.
