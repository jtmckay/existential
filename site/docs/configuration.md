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
    + EXIST_PUBLIC_DOMAIN  (needs a value)
```

`git pull && ./existential.sh` is the upgrade. It never:

- changes a value you set
- fills a blank (blank means something: "not asked yet", or "use the global URL")
- removes a key (`./existential.sh validate drift` lists extras)
- asks a question: a key that needs input arrives blank, marked `(needs a value)`

New services arrive with their flag `false`.

Images work differently: when a template names a different image than your rendered compose
file, the run lists it and asks before updating the file. Each run then pulls and builds every
enabled image without touching running containers; `docker compose up -d` switches to them.

## Service enablement

`EXIST_IS_<CATEGORY>_<SLUG>=true|false`, one per service folder
([The Pieces](./how-it-works.md#1-choose--a-flag-per-service)). Set by hand or by
`./existential.sh flow on <name>`.

## Models

Every model is named once, in the *Model Selection* block; everything else reads it. The block
is filled from a tier table when the first GPU service is enabled (**GPU vendor**, then
**VRAM**). To change it:

```bash
./existential.sh run models
```

After editing anything in the block by hand:

```bash
./existential.sh                        # re-renders honcho's config
./existential.sh run ollama pull-models
```

### The VRAM budget

On one card, at all times:

```
chat model  +  bge-m3 (1.2 GB)  +  KV cache  <  your VRAM
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
| `bge-m3` | 1.2 GB | embeddings | every tier |

- Up to 24 GB is quantised; 96 GB runs full precision.
- Every tier runs 64k context (hermes needs it). Below about 12 GB the KV cache spills to RAM
  and runs slower.
- The table is `src/utils/model-tiers.sh`. Edit it there; a unit test checks it matches.

### Traps

- **gemma4 "E" tags** count *effective* parameters, not size: `gemma4:e4b` downloads at 9.6 GB.
  Use the `-qat` tags above.
- **Mixture-of-experts** models keep every expert resident: a 30B model with 3B active is still
  25 GB.

### Rules for any model you pick

- It **must** have ollama's `tools` capability, or hermes can't act.
- Prefer multimodal, so images don't evict it for a separate vision model.
- `EXIST_MODEL_CHAT_NUM_CTX` is a **floor of 65536**. Below it ollama silently truncates hermes'
  prompt. Raising it costs VRAM.
- `EXIST_MODEL_EXTRACT` and `EXIST_MODEL_VISION` ship as the chat tag, so one model stays loaded.
  Blank `EXIST_MODEL_VISION` disables image handling.
- `EXIST_MODEL_EMBED` is the same on every tier. Changing it after ingestion corrupts the vector
  index: wipe `volumes/openviking_data`. `EXIST_MODEL_EMBED_DIM` must match: `bge-m3` → 1024,
  `nomic-embed-text` → 768, `mxbai-embed-large` → 1024.
- Speech runs on CPU (wyoming-whisper, wyoming-piper):
  - `EXIST_MODEL_STT`: `tiny | base | small | medium | large-v3`
  - `EXIST_MODEL_TTS_VOICE`: a piper voice, `<lang>_<REGION>-<name>-<quality>`
    ([samples](https://rhasspy.github.io/piper-samples/))
  - `EXIST_MODEL_STT_LANGUAGE`: the language you speak (`en` by default); short commands need it
  - WhisperX is separate: GPU, long recordings, speaker labels.

<a id="endpoints"></a>

## Endpoints — putting roles on different machines

`EXIST_MODEL_URL` (default `http://ollama:11434/v1`) is the **OpenAI-compatible `/v1` URL**
every role uses unless it has its own: local ollama, ollama elsewhere, llama.cpp
(`http://192.168.1.20:8080/v1`), anything that answers `/v1/chat/completions`.

- Every caller speaks only `/v1`, so the backend doesn't matter.
- Ollama-only steps (pull, `run ollama unload`, `/api/show`) run only with `EXIST_IS_AI_OLLAMA=true`.
- The embed server must serve `/v1/embeddings` (llama.cpp: `--embeddings`); the vision server
  must accept images (llama.cpp: `--mmproj`).
- Models elsewhere: set `EXIST_IS_AI_OLLAMA=false`.

The **Model Endpoints** block sends each role somewhere different. Every key ships **blank**,
meaning "use `EXIST_MODEL_URL`".

| Key | Role | Who reads it |
|---|---|---|
| `EXIST_MODEL_URL_CHAT` | Chat / reasoning | hermes, open-webui, decree scripts, the newsletter |
| `EXIST_MODEL_URL_EXTRACT` | Background extraction | honcho's deriver and dialectic |
| `EXIST_MODEL_URL_EMBED` | Embeddings | openviking's vector store, honcho |
| `EXIST_MODEL_URL_VISION` | Vision / OCR | image-ocr |

A worked split, with a 24 GB card and an 8 GB one:

```bash
EXIST_MODEL_URL=http://bigbox:8080/v1             # chat and extraction land here
EXIST_MODEL_URL_EMBED=http://littlebox:11434/v1
EXIST_MODEL_URL_VISION=http://littlebox:11434/v1
```

Chat keeps the big card; embeddings and OCR stop evicting it. Then `./existential.sh` and
`docker compose restart honcho hermes-agent openviking`.

- `./existential.sh run models` prints where each role resolves. Migrations pull each model to
  the machine that serves it.
- The old `EXIST_OLLAMA_URL*` keys are carried over on upgrade, `/v1` added.
- [A Separate AI Box](./hosting/ai-box): llama.cpp presets, ComfyUI, on-demand TTS.

ComfyUI moves the same way, with `EXIST_COMFYUI_URL` (default `http://comfyui:8188`):

```bash
EXIST_COMFYUI_URL=http://bigbox:8188
EXIST_IS_AI_COMFYUI=false                  # nothing local to start
```

Two things don't follow the block:

- Hermes' `config.yaml` `base_url` is updated each run only while it points at an ollama
  (`:11434`). One you set by hand is left alone.
- OpenViking writes `ov.conf` once. Delete it and re-run to repoint.

### Speech has no endpoint keys

They run on CPU, and Home Assistant addresses them by host and port in its own settings. To
move one: publish its port on the other machine (the commented `ports:` block), disable it here,
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
| `external` | Same treatment as `none` — this machine has no card to reserve. Ollama is not run locally at all; the models come from `EXIST_MODEL_URL` on another machine. |

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
  works. ntfy and the digest's links use it. See [Core over Tailscale](./how-it-works.md#core-over-tailscale).

The rest are for Caddy ([Hostnames that just work](./how-it-works.md#hostnames-that-just-work)):

- **`EXIST_LOCAL_HOST_IP`**: detected (LAN address, or the tailnet address with Tailscale up).
  Keep it **above** `EXIST_DOMAIN` in the file; placeholders resolve top-down.
- **`EXIST_DOMAIN`**: defaults to `<ip-with-dashes>.nip.io`. Never a MagicDNS name: there's no
  wildcard under one.
- **`EXIST_PUBLIC_DOMAIN`**: adds Let's Encrypt certs. Needs a domain you own, `<domain>` and
  `*.<domain>` pointing at your public IP, and ports 80 and 443 forwarded. Then
  `./existential.sh run caddy public-domain`.

`docker compose up` creates the `exist` network.

## Storage

- Data is host bind mounts under `<repo>/volumes/<name>`, never Docker volumes.
- **`EXIST_NFS_ADDRESS`**: the NAS's NFS address, asked the first run a service with an
  `nfs: true` volume is on. Blank is not yet asked; `none` keeps every volume local.
- **`EXIST_NFS_PATH_<VOLUME>`**: one per `nfs: true` volume of an enabled service, appended when
  asked: that volume's folder on the export, or `local`. Compose mounts it over NFS. See
  [Storage](./storage/#a-nas-for-the-bulk-files).
- **`EXIST_BACKUP_RCLONE_REMOTE`**: an rclone remote (`<remote>:<path>`), set by
  `./existential.sh run rclone`. Blank disables scheduled DB backups.

## Shared service credentials

Generated on render, shared between services:

- **`EXIST_HERMES_API_KEY`**: the hermes gateway key (hermes-agent, open-webui).
- **`EXIST_NTFY_URL`**: ntfy, by container name. `EXIST_NTFY_USER` / `EXIST_NTFY_PASSWORD` are
  the publisher, created by ntfy on first boot.
- **`EXIST_DECREE_FILES_WEBHOOK_AUTH_TOKEN`**: what Nextcloud's file-event webhooks send to
  `/files`. See [File Processor](./decree/file-change-processing#setup).
- **`EXIST_NEXTCLOUD_DOMAIN`, `_USER`, `_APP_PASSWORD`, `_WORKSPACE_DIR`**: the Nextcloud
  `workspace/` syncs with. See [Syncing with a Nextcloud](./getting-started#syncing-with-a-nextcloud-optional).
