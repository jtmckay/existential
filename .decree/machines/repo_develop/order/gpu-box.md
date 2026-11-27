---
machine: repo_develop
---
# A worked guide for a separate GPU box, its one card taken in turns

## Overview

Many people keep their GPU models on a separate computer. The maintainer's own box is a good
worked example: one 24 GB card, rootless podman with NVIDIA CDI, llama.cpp in router mode,
ComfyUI, Strata, TTS, and a CPU GLiNER classifier. Only one GPU-heavy service fits at a time,
so the card is taken in turns.

## Outcome

- `site/docs/hosting/ai-box.md` is a guide to running a separate AI box and pointing the stack
  at it. It covers:
  - one card taken in turns: `lease_gpu` (a host plugin extending decree's `decree_lease`) on
    the box, where a lease unloads the others first, asked for from the box or another host
    through the box's lease API, `hosting/fleet-api` (decree-go-rest pulled as an image, run by
    Compose with `restart: unless-stopped`, on `:8801` behind the fleet secret), turned on by
    `./existential.sh run fleet api`; nothing starts it from the host;
  - GPU containers under rootless podman with CDI;
  - llama.cpp's router-mode command and presets, including why the V-cache type sits per
    model in the preset rather than on the command line;
  - ComfyUI, Strata and TTS, each a lease like the others, started at boot by `boot_daemon`
    (`.decree/boot.sh`, one `tmx` line per process);
  - checking it works, GLiNER on CPU, and which stack keys to set (`AI_BOX_*` in the box's
    `.decree/.env`; the stack reaches models through the controller's offers, `04-models.md`).
- The guide links from the hosting docs, Configuration's model endpoints, and Controller and
  Workers.

## Constraints

- No usernames, hostnames, IP addresses or paths under a home directory: `<ai-box>` and `~/`
  placeholders.
- Where a detail of the example box is unknown, the guide omits it rather than inventing it.

## Acceptance Criteria

- **Given** the docs site build
  **Then** it succeeds and the guide is reachable from the Hosting overview
- **Given** `./existential.sh test ai-box-guide`
  **Then** it exits 0: no username, IP address or `/home/` path in the guide
