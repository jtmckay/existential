---
sidebar_position: 2
---

# Getting Started

One evening of setup, then it runs.

## What you need

- A computer to leave on: Linux, or a Mac with Docker Desktop. On Windows, run everything
  inside WSL2, with the repo cloned on the Linux side (not under `/mnt/c`).
- [Docker](https://www.docker.com/get-started/), usable without sudo
  (`sudo usermod -aG docker "$USER"`, then reboot). Docker Desktop: turn on *Start Docker Desktop
  when you sign in*, so the stack starts with the computer.
- Optional, and worth it: [Tailscale](https://tailscale.com/download), logged in on that computer
  and on your phone and laptop. It gives every device a private, trusted address for the stack,
  at home or away.

## Install

```bash
git clone https://github.com/jtmckay/existential.git
cd existential
./existential.sh
docker compose up -d
```

The first run asks what this computer is:

- **Core** (Enter): [Core](./intro.md#what-core-installs) and nothing more. It asks for a
  username (Enter keeps `admin`) and a password (Enter generates one), prints both at the end,
  and keeps them in `.env.shared`.
- **A worker**: for when you have more than one computer, set up as
  [Controller and Workers](./hosting/controller-and-workers.md) describes. Not for your first.

Every answer is kept as soon as you give it, and anything the computer is missing is offered
for install with the command shown: Enter installs it and setup goes on. It prints where to
open it: with Tailscale, `https://<computer>.<tailnet>.ts.net`; without,
`http://<computer's address>:42080`.

That is code-server, your workspace in a browser tab. Start `claude` in its terminal and `/login`
once; that signs in the automations too.

## Point it at a model

In `.env.shared`:

- `EXIST_MODEL_URL`: any OpenAI-compatible address ending `/v1`: a hosted LLM, a server of your
  own, or your [controller](./hosting/controller-and-workers.md)'s, which lends out a GPU host.
- `EXIST_MODEL_KEY`: the API key a hosted LLM wants.
- `EXIST_MODEL_CHAT`: the model. Blank is the first one the server lists.

Then `./existential.sh && docker compose up -d`. Until then, the routines that need a model
skip.

## Get notifications on your phone

Install the [ntfy](./services/ntfy.md) app and subscribe to the address the run printed. That is
how the stack reaches you: the morning digest, a routine that needs an answer, something broken.

## Turn on what you want

[What It Does](./flows/index.md) is the list: each problem, and the lines that turn it on. A
few are on from the start. The two kinds of line:

```bash
./existential.sh service on whisperx     # an app; then docker compose up -d
./existential.sh plugin on newsletter    # a routine, installed at once
```

Bare `./existential.sh service` is a picker. `service off` and `plugin off` turn one off.

## Back it up

Core ships no backups. Turn on [Backups](./flows/looks-after-itself.md#backups), or put
`volumes/workspace_data` under git with a remote you choose.

## Upgrade

```bash
git pull && ./existential.sh && docker compose up -d
```

Your settings and edits are never overwritten: new settings are added to your `.env` files and
listed, and newer app versions are listed and applied if you say yes. Or have it
[update itself](./flows/looks-after-itself.md#staying-up-to-date).

## If something isn't right

- **Is everything working?** `./existential.sh test services`: every app you have on checks
  itself.
- **Tailscale couldn't serve yet:** the run says what is missing, usually *MagicDNS* and *HTTPS
  Certificates* in the [admin console](https://login.tailscale.com/admin/dns), or
  `sudo tailscale set --operator=$USER` once.
- **Apps beyond Core** have names like `https://<app>.<domain>`, which need Caddy:
  [Networking](./networking.md).
- **A GPU:** the first app that wants one asks which you have, once. Change the answer with
  `./existential.sh run models`. [Configuration](./configuration.md#gpu-vendor).
- **More than one computer:** [Controller and Workers](./hosting/controller-and-workers.md).
