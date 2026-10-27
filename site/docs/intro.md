---
sidebar_position: 1
slug: /intro
---

# What It Is

:::info[Level 1 of 4 · Context]
The system as one box — what it is and what it does for you. Zoom in one step at
[Level 2 · The Pieces](./how-it-works).
:::

**Your best brain day now accessible.**

Can't remember what you've forgotten? Change your environment to remember for you. Existential is that environment. It's just a notepad, until you tell it what to do.

Everything else on your phone surfaces what someone else decided needs your attention. This
surfaces what you decided. What you're building is your Diagram: the plan from your best day,
followed on the rest.

Underneath it is a curated set of open-source apps (notes, photos, money, files, dashboards,
monitoring, home automation) run as one system: each with a name you can type, a certificate
your phone trusts, somewhere safe to put its data, a backup, and a way to reach the others.
You choose what you want; it comes up wired together.

## Three things it gets you

### Written down, not remembered
A decision is a file. It runs whether or not you remember making it.

### Plain files
Everything you build is a file you can read. Nothing is locked inside an app you'll move on from.

### Yours, physically
It runs on hardware you own. No account to lose, no subscription required, nobody who can lock
you out.

## What it looks like from outside

```mermaid
flowchart TB
    you["<b>You</b><br/><i>phone · laptop · your voice</i>"]
    outside["<b>The outside world</b><br/><i>bank email · calendars · the web</i>"]

    subgraph house["Your house — one machine, one network"]
        ex["<b>Existential</b><br/>your apps · your storage<br/>your automations · the AI you choose"]
    end

    you <--> ex
    outside -. "pulled in when you ask" .-> ex

    classDef me fill:#e8f4fd,stroke:#027bcb,stroke-width:2px,color:#111
    classDef core fill:#027bcb,stroke:#014d80,stroke-width:2px,color:#fff
    classDef ext fill:#f4f4f4,stroke:#999,stroke-dasharray:4 3,color:#333
    class you me
    class ex core
    class outside ext
    style house fill:#fcfcfc,stroke:#027bcb,stroke-width:2px,color:#014d80
```

Three things worth noticing about that picture:

- **You talk to one system**, not to twenty apps you have to remember the addresses of.
- **The boundary is real.** Data comes in from outside; nothing goes back out unless you
  wrote a routine that sends it.
- **Everything inside the box is yours** — plain files, on disks you own, readable without
  Existential running at all.

## The AI is part of the plumbing, not a feature

Most stacks bolt an assistant on the side. Here it sits underneath, and everything reaches it
the same way:

| You want to… | You get… |
|---|---|
| **Ask for something out loud** | A conversation, anywhere in the house, in a voice you chose |
| **Hand off a piece of work** | An agent that reads your notes and the web and files the answer back in your workspace |
| **Not do a chore again** | A routine that runs on a trigger and only speaks up when it matters |

All three reach the same model, at one OpenAI-compatible URL. Swap what serves it — a bigger
model, a box with more VRAM — and all three change at once.

*Which projects actually provide this is [Level 2](./how-it-works). It's deliberately not on
this page: the pieces are replaceable, the shape isn't.*

## What Core installs

The first `./existential.sh` builds **Core**: open the work dir, talk to an AI about it,
have decree automate it. It runs on one ordinary box, with no GPU and no model downloads, and
Tailscale on the host gives it real HTTPS on every device you log in.

| | |
|---|---|
| [code-server](./services/code-server) | Your work dir, `workspace/`, in a browser tab: editor, plus a terminal with `claude` and `opencode` ready |
| [Decree](./decree/) | Runs the automations in `workspace/.decree/` on a schedule or an inbox message |
| [ntfy](./services/ntfy) | How an automation tells you it finished, failed or is waiting for you |

Everything else (Caddy hostnames, monitoring, the webhook and Nextcloud for capture, apps,
local models and agents, voice and Home Assistant) is an optional add-on, one flow or one flag
away. What each piece does is [Level 2](./how-it-works).

## Try it

Prerequisites: [Docker](https://www.docker.com/get-started/) usable without sudo, a machine to
host it, this repo, and, for Core, [Tailscale](https://tailscale.com/download) logged in on that
machine and on every device that should reach it.

```bash
git clone https://github.com/jtmckay/existential.git
cd existential

./existential.sh            # asks for a username and password, builds Core
docker compose up -d
```

Full walkthrough in [Getting Started](./getting-started).
