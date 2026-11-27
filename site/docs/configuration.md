---
sidebar_position: 3
sidebar_label: Configuration
---

# Configuration

Host settings live in `.env.shared` (rendered once from `.env.exist.shared`, gitignored).
`./existential.sh` merges it into the root `.env`. The file has one comment line per key; this
page has the detail.

## What happens when you `git pull`

Rendered files are never overwritten. Instead, each run appends any key your `.env` file is
missing, with its comment, and lists it:

```
  updated: .env.shared — 2 new key(s) from the template
    + EXIST_NTFY_USER
    + EXIST_NFS_ADDRESS  (needs a value)
```

`git pull && ./existential.sh` is the upgrade. It never:

- changes a value you set
- fills a blank (blank means something: "not asked yet", or "use the global URL")
- removes a key (`./existential.sh validate drift` lists extras)
- asks a question: a key that needs input arrives blank, marked `(needs a value)`

New services arrive with their flag `false`.

Images work differently: when a template names a different image than your rendered compose
file, the run lists it and asks before updating the file (with no terminal to ask, as under the
`pull_existential` plugin, it updates it). Each run then pulls and builds every
enabled image without touching running containers; `docker compose up -d` switches to them.

## Service enablement

`EXIST_IS_<CATEGORY>_<SLUG>=true|false`, one per service folder
([Services](./how-it-works.md#1-choose--a-flag-per-service)). Set by hand or by
`./existential.sh service on <slug>`.

## Models

Every model is named once, in the *Model Selection* block; everything else reads it. Three keys
point the stack at a model:

| Key | |
|---|---|
| `EXIST_MODEL_URL` | Any OpenAI-compatible base URL ending `/v1`: a hosted LLM, a server of your own, or your controller's model endpoint. Blank: no model yet, and what needs one skips. |
| `EXIST_MODEL_KEY` | The API key that URL wants. Blank sends `EXIST_FLEET_SECRET`, which a controller takes. |
| `EXIST_MODEL_CHAT` | The chat model. Blank: the first model the URL lists (`/v1/models`). |

With a local GPU, the block is filled from a tier table when the first GPU service is enabled
(**GPU vendor**, then **VRAM**), and turning on Ollama points `EXIST_MODEL_URL` at it. To change
the tier:

```bash
./existential.sh run models
```

After editing the block by hand, with Ollama on:

```bash
./existential.sh run ollama pull-models
docker compose up -d                    # recreates what reads the models
```

### The VRAM budget

On one card, at all times:

```
chat model  +  KV cache  <  your VRAM
```

Download sizes:

| Tag | Size | Capabilities | Tier |
|---|---|---|---|
| `qwen3-vl:2b` | 1.9 GB | tools, vision | CPU-only |
| `qwen3-vl:4b` | 3.3 GB | tools, vision | 6 GB |
| `gemma4:e2b-it-qat` | 4.3 GB | tools, vision | 8 GB (default) |
| `gemma4:e4b-it-qat` | 6.1 GB | tools, vision | 12 GB |
| `gemma4:12b-it-qat` | 7.2 GB | tools, vision | 16 GB |
| `gemma4:26b-a4b-it-qat` | 16 GB | tools, vision | 24 GB |
| `gemma4:31b-it-bf16` | 63 GB | tools, vision | 96 GB (bf16) |

- Up to 24 GB is quantised; 96 GB runs full precision.
- Every tier runs 64k context (an agent's tool loop needs it). Below about 12 GB the KV cache spills to RAM
  and runs slower.
- The table is `src/utils/model-tiers.sh`. Edit it there; a unit test checks it matches.

### Traps

- **gemma4 "E" tags** count *effective* parameters, not size: `gemma4:e4b` downloads at 9.6 GB.
  Use the `-qat` tags above.
- **Mixture-of-experts** models keep every expert resident: a 30B model with 3B active is still
  25 GB.

### Rules for any model you pick

- It **must** have ollama's `tools` capability, or pi can't act.
- Prefer multimodal, so images don't evict it for a separate vision model.
- `EXIST_MODEL_CHAT_NUM_CTX` is a **floor of 65536**. Below it ollama silently truncates an
  agent's prompt. Raising it costs VRAM.
- `EXIST_MODEL_VISION` ships as the chat tag, so one model stays loaded.
  Blank `EXIST_MODEL_VISION` disables image handling.
- Speech runs on CPU, and its settings are the services' own:
  [wyoming-whisper](./ai/wyoming-whisper.md) and [wyoming-piper](./ai/wyoming-piper.md).
  WhisperX is separate: GPU, long recordings, speaker labels.

<a id="endpoints"></a>

## Endpoints — where model calls go

`EXIST_MODEL_URL` (default `http://ollama:11434/v1`) is this host's **OpenAI-compatible `/v1`
URL**: local ollama, ollama elsewhere, llama.cpp (`http://192.168.1.20:8080/v1`), anything that
answers `/v1/chat/completions`.

- Every caller speaks only `/v1`, so the backend doesn't matter.
- Ollama-only steps (pull, `run ollama unload`, `/api/show`) run only with `EXIST_IS_AI_OLLAMA=true`.
- Models elsewhere: set `EXIST_IS_AI_OLLAMA=false`.
- `EXIST_FLEET_SECRET` (generated) is sent as a bearer token on every model call. ollama ignores
  it; [Strata](./ai/strata.md) requires it, and a llama.cpp server takes it with `--api-key`.

To spread models across hosts, put them on a [GPU box](./hosting/ai-box.md) and lease them.
With `EXIST_FLEET_SECRET` set, the stack's decree scripts (model calls, pi, OCR) ask the
controller which host serves the model `EXIST_MODEL_CHAT` (or `EXIST_MODEL_VISION`) names, and
use it under that host's lease ([Leases](./hosting/controller-and-workers.md#leases)). ComfyUI
works the same way. A model no host offers goes to `EXIST_MODEL_URL`. Apps that cannot take a
lease (Open WebUI, opencode, Home Assistant) always use `EXIST_MODEL_URL`.


### Speech has no endpoint keys

They run on CPU, and Home Assistant addresses them by host and port in its own settings. To
move one: publish its port on the other host (the commented `ports:` block), disable it here,
and point Home Assistant at it.

## GPU vendor

`EXIST_GPU_VENDOR`: `nvidia`, `amd`, `none` or `external`. Asked once, when the first GPU service
is enabled (never for Core). Ships blank, meaning not yet asked. Change it with
`./existential.sh run models`.

What it changes, in `src/generate-compose.ts`:

| Value | Effect |
|---|---|
| `nvidia` | Nothing. The templates already declare the nvidia device reservation. |
| `amd` | The nvidia reservation is stripped, and each service's `x-exist-gpu.amd` block is merged in instead (Vulkan/ROCm). |
| `none` | The nvidia reservation is stripped, and `x-exist-gpu.none` merged. |
| `external` | Same treatment as `none` — this host has no card to reserve. Ollama is not run locally at all; the models come from `EXIST_MODEL_URL` on another host. |

- One nvidia reservation on a host without the runtime fails `docker compose up` for the whole
  stack, which is why it's stripped.
- Blank falls back to `EXIST_VRAM_GB` (`0` → `none`, a number → `nvidia`); both blank → `none`.
- `external` turns off local Ollama and asks for a model URL. That's how a GPU-less machine runs
  the agent path.
- e2e runs a tiny model set on CPU (`src/test/fixtures/env.shared`), so it needs no card.

`EXIST_VRAM_GB` is the tier picked; it also ships blank.

- **Custom** (last entry) takes a model name, sets the `EXIST_MODEL_*` keys, and checks nothing.
  The model needs tool calling, vision and 64k context.
- `0` is CPU-only, set by answering *No GPU*. Expect seconds per token.

## Identity and permissions

- **`EXIST_USERNAME` / `EXIST_PASSWORD`**: your login for ntfy and every admin account a service
  creates. Blank until a service that needs them is first turned on (Core does), then asked
  once. Enter gives `admin` and a generated 24-character
  password, which is never printed. A typed password must be 8+ characters of `A-Za-z0-9._-`
  (it's written unquoted into many files).
- **`EXIST_EMAIL`**: blank until an add-on that needs one (Open WebUI, NocoDB, Appsmith) is first
  enabled, then asked once.
- **`EXIST_PUID` / `EXIST_PGID`**: the user and group every container runs as, so files in volumes
  stay yours. Detected from `id -u` / `id -g` on the first run.

## Hostnames, DNS and TLS

- **`EXIST_TAILNET_NAME`**: Core's address (`box.tail1234.ts.net`), set once `tailscale serve`
  works. ntfy and the digest's links use it. See [Core over Tailscale](./networking.md#core-over-tailscale).
- **`EXIST_CONTROLLER`**: with `report_host` on, the controller this host reports to, its
  tailnet name, 100.x address, or address on your own network. Blank, this host is the
  controller, and has Loki on. See [Controller and Workers](./hosting/controller-and-workers.md).
- **`EXIST_FLEET_SECRET`**: the same on every host; the secret for leasing another host's GPU
  ([Leases](./hosting/controller-and-workers.md#leases)) and every model call. Generated on the
  first run; copy the controller's to every other host (`fleet join` does).

The rest are for Caddy ([Hostnames that just work](./networking.md#every-other-app-caddy)):

- **`EXIST_LOCAL_HOST_IP`**: detected (LAN address, or the tailnet address with Tailscale up).
  Keep it **above** `EXIST_DOMAIN` in the file; placeholders resolve top-down.
- **`EXIST_DOMAIN`**: defaults to `<ip-with-dashes>.nip.io`. Never a MagicDNS name: there's no
  wildcard under one.

`docker compose up` creates the `exist` network.

## Storage

- Data is host bind mounts under `<repo>/volumes/<name>`, never Docker volumes.
- **`EXIST_NFS_ADDRESS`**: the NAS's NFS address, asked the first run a service with an
  `nfs: true` volume is on. Blank is not yet asked; `none` keeps every volume local.
- **`EXIST_NFS_PATH_<VOLUME>`**: one per `nfs: true` volume of an enabled service (e.g.
  `EXIST_NFS_PATH_NEXTCLOUD_DATA`), appended when asked: that volume's folder on the NAS, or
  `none` (Enter) to keep it on this host. Compose mounts it over NFS.
- **`EXIST_NFS_SHARE_<NAME>`**: the same for a volume that holds your own files rather than a
  container's data: `EXIST_NFS_SHARE_NEXTCLOUD` (shown in Nextcloud at `/nas`) and
  `EXIST_NFS_SHARE_WORKSPACE` (where `workspace/` syncs to) and `EXIST_NFS_SHARE_NOTES` (a notes
  vault `notes-pull` copies into `workspace/notes/`, read-only). See
  [Storage](./storage/index.md#a-nas-for-the-bulk-files).
- **`EXIST_BACKUP_RCLONE_REMOTE`**: an rclone remote (`<remote>:<path>`), set by
  `./existential.sh run rclone`. Blank disables scheduled DB backups.

## Shared service credentials

Generated on render, shared between services:

- **`EXIST_NTFY_URL`**: ntfy, by container name. `EXIST_NTFY_USER` / `EXIST_NTFY_PASSWORD` are
  the publisher, created by ntfy on first boot. On a host with ntfy off and a controller, `.env`
  gets the controller's Loki instead, which relays to its ntfy; any other address naming a
  service that is off here gets the controller's domain. See
  [Controller and Workers](./hosting/controller-and-workers.md#services-a-host-has-off).
- **`EXIST_DECREE_FILES_WEBHOOK_AUTH_TOKEN`**: what Nextcloud's file-event webhooks send to
  `/files`. See [File Processor](./plugins/file-change-processing.md#setup).
- **`EXIST_NEXTCLOUD_DOMAIN`, `_USER`, `_APP_PASSWORD`, `_WORKSPACE_DIR`**: the Nextcloud
  `workspace/` syncs with. See [Syncing with a Nextcloud](./flows/one-place.md#the-workspace-on-your-other-devices).
