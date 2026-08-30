---
sidebar_position: 3
sidebar_label: Configuration
---

# Configuration

Everything host-specific lives in one file at the repo root: `.env.exist.shared` (the
template) renders once into `.env.shared` (yours, gitignored). Every service reads from
it, and `./existential.sh` merges it into the single `.env` the stack runs on.

The file itself carries one line per key. This page is the long version — why each value
exists, what breaks when you change it, and which ones you should never set by hand.

## What happens when you `git pull`

Rendered files are written once and never overwritten — that is what keeps your edits and your
generated secrets. On its own that would mean a key added upstream never reached you: your
`.env.shared` already exists, so it gets skipped, and the new setting is silently empty
everywhere that reads it.

So `./existential.sh` reconciles `.env` files by **key** on every run. Any key the template has
and your file does not is appended in a stamped block at the end, with its comment, and named in
the output:

```
  updated: .env.shared — 2 new key(s) from the template
    + EXIST_NTFY_USER
    + EXIST_PUBLIC_DOMAIN  (needs a value)
```

`git pull && ./existential.sh` is the upgrade. Four things it will never do:

- **Change a value you set.** It only ever appends keys that are absent.
- **Fill in a blank.** Blank is meaningful here — `EXIST_VRAM_GB` blank means "not asked yet",
  and a blank `EXIST_OLLAMA_URL_<ROLE>` means "fall back to the global URL".
- **Remove anything.** A key you added that the template lacks stays.
  `./existential.sh validate drift` lists those.
- **Ask you a question.** A key that needs your input arrives blank and is flagged
  `(needs a value)` — fill it in and re-run.

New services arrive switched off, since their `EXIST_IS_<CATEGORY>_<SLUG>` flag is appended as
`false`. Run `./existential.sh quest` to turn one on.

## Service enablement

`EXIST_IS_<CATEGORY>_<SLUG>=true|false`, one per service folder. That flag is the whole
plugin system: see [The Pieces](./how-it-works.md#1-choose--a-flag-per-service). Set them
by hand, or run `./existential.sh quest` and pick from a list.

## Models

Every model the stack uses is named **once**, in the *Model Selection* block. Nothing
hardcodes a tag: the ollama migrations pull what is named here, honcho renders its
`config.toml` from it, openviking's vector store reads it, and hermes takes it as config.

You do not normally edit this block by hand. `./existential.sh` asks two questions on the
first run — **GPU vendor**, then **VRAM** — and fills the block in from a tier table.
Change your mind later with:

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

Measured download sizes, so you can sanity-check a swap:

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

Everything up to 24 GB is quantised; the 96 GB tier is the only one that runs the weights
at full precision, which is what that much memory actually buys.

The KV cache is the third term, and it is not small: every tier runs 64k context because
hermes requires it. Below roughly 12 GB that cache does not fit alongside the weights, so
it spills into system RAM and ollama offloads layers to the CPU. Those tiers are still
supported — the cost is tokens per second, not capability.

The tier table itself lives in `src/utils/model-tiers.sh`, with the reasoning for every
size. Edit the table, not the individual values — a unit test asserts the two agree.

### Two traps worth knowing

**gemma4's "E" tags.** The E in `e2b`/`e4b` means *effective* parameters — a claim about
compute, not file size. `gemma4:e4b` is an 8B model that downloads at 9.6 GB, and
`gemma4:e2b` at 7.2 GB. The `-qat` (quantization-aware trained) variants above are the
ones that actually fit; the plain q4 tags do not.

**Mixture-of-experts sizes.** `nemotron-3.5-lightning` is 30B with only 3B active per
token, which sounds small and is not: every expert stays resident, so it is a 25 GB model
that merely runs at 3B speed.

### Rules for any model you pick

- It **must** have ollama's `tools` capability, or hermes can talk but not act.
- Prefer a multimodal tag, so images go to the model already loaded instead of evicting it
  for a separate vision model.
- `EXIST_MODEL_CHAT_NUM_CTX` is a **floor of 65536**, not a tuning knob. Hermes' system
  prompt carries skills, memory and MCP tool definitions. Below 64,000 tokens ollama does
  not error — it silently truncates, which reads as the agent ignoring its instructions.
  Raising it costs VRAM (the KV cache grows with it); lowering it breaks hermes.
- `EXIST_MODEL_EXTRACT` and `EXIST_MODEL_VISION` ship as the *same tag* as chat, so only
  one model stays resident. Split them only if you have VRAM for two at once. Blanking
  `EXIST_MODEL_VISION` disables image handling entirely.
- `EXIST_MODEL_EMBED` does **not** vary by tier, and changing it after first ingestion
  corrupts the vector index — the dimensions no longer match what is already stored. Wipe
  `volumes/openviking_data` if you do. `EXIST_MODEL_EMBED_DIM` must match it: `bge-m3` →
  1024, `nomic-embed-text` → 768, `mxbai-embed-large` → 1024.
- Speech-to-text and text-to-speech deliberately run on **CPU** (wyoming-whisper,
  wyoming-piper) so they never compete with the LLM for VRAM. `EXIST_MODEL_STT` takes
  `tiny | base | small | medium | large-v3`; `EXIST_MODEL_TTS_VOICE` takes a piper voice
  (`<lang>_<REGION>-<name>-<quality>` — browse and listen at
  [piper-samples](https://rhasspy.github.io/piper-samples/)). This is not whisperx: that
  one runs on the GPU and transcribes long recordings with speaker labels.

## Endpoints — putting roles on different machines {/* #endpoints */}

`EXIST_OLLAMA_URL` (default `http://ollama:11434`) is the address every model role uses
unless it has one of its own. Point it at another machine — `http://192.168.1.20:11434` — to
run the models on a GPU box while the rest of the stack stays here, and disable
`EXIST_IS_AI_OLLAMA` if nothing local serves them.

The **Model Endpoints** block in `.env.shared` then lets each role go somewhere different, so
VRAM is spread rather than shared. Every key ships **blank**, and blank means "wherever
`EXIST_OLLAMA_URL` points" — leave them alone and nothing changes.

| Key | Role | Who reads it |
|---|---|---|
| `EXIST_OLLAMA_URL_CHAT` | Chat / reasoning | hermes, open-webui |
| `EXIST_OLLAMA_URL_EXTRACT` | Background extraction | honcho's deriver and dialectic |
| `EXIST_OLLAMA_URL_EMBED` | Embeddings | openviking's vector store, honcho |
| `EXIST_OLLAMA_URL_VISION` | Vision / OCR | image-ocr, telegram-receipt |

A worked split, with a 24 GB card and an 8 GB one:

```bash
EXIST_OLLAMA_URL=http://bigbox:11434       # chat and extraction land here
EXIST_OLLAMA_URL_EMBED=http://littlebox:11434
EXIST_OLLAMA_URL_VISION=http://littlebox:11434
```

Chat keeps the big card to itself; embeddings and OCR — small models under bursty load — stop
evicting it. Re-run `./existential.sh` to propagate, then
`docker compose restart honcho hermes-agent openviking`.

`./existential.sh run models` prints where each role currently resolves, and the roles are the
same vocabulary `ollama-pull` uses, so a migration pulls each model **to the machine that will
serve it** with no per-migration edits.

Two things do not follow the block:

- Hermes stores the endpoint in its own `config.yaml`, so `exist.initial.sh` reconciles that
  `base_url` on every run — but only while it still points at an ollama (`:11434`). A
  `base_url` you aimed at some other provider by hand is a preference and is left alone.
- OpenViking writes `ov.conf` once. Delete it and re-run to repoint an existing install.

### Speech has no endpoint keys

`wyoming-whisper` and `wyoming-piper` run on **CPU** by design, so moving them frees no VRAM and
there is nothing for this block to spread. They are also reached over raw TCP, addressed by a
host and port typed into Home Assistant's Wyoming integration — which no file in this repo
controls. To run one on another machine, publish its port there (the commented `ports:` block in
that service's compose file), disable the service here, and point Home Assistant at the other
host.

## GPU vendor

`EXIST_GPU_VENDOR` is `nvidia`, `amd`, or `none`. It is the **first** question quest asks,
and its presence is the record of having asked — quest never re-asks once it is set, and
`./existential.sh run models` is the way back. It ships **blank** for that reason: a value
in the template means the first run never gets to ask.

What it changes, all in `src/generate-compose.ts`:

| Value | Effect |
|---|---|
| `nvidia` | Nothing. The templates already declare the nvidia device reservation. |
| `amd` | The nvidia reservation is stripped, and each service's `x-exist-gpu.amd` block is merged in instead (Vulkan/ROCm). |
| `none` | The nvidia reservation is stripped, and `x-exist-gpu.none` merged. |

The strip is not cosmetic: docker refuses to create a container whose device driver it
cannot satisfy, so one nvidia-reserving service takes down `docker compose up` for the
*whole* stack on a host without that runtime. Blank is treated as `nvidia`, which is what
every install predating this setting already assumed.

`EXIST_VRAM_GB` records the tier that was picked, and likewise ships blank. `0` is the
CPU-only tier — you normally reach it by answering *No GPU* to the vendor question, which
sets it for you and skips the VRAM question, since a VRAM number means nothing without a
card. Expect seconds per token, not tokens per second; the wyoming voice services are
unaffected, they are CPU already.

## Identity and permissions

`EXIST_EMAIL`, `EXIST_USERNAME` and `EXIST_PASSWORD` are the default credentials seeded
into services that need an admin account on first boot.

`EXIST_PUID` / `EXIST_PGID` are the host user and group every container runs as
(referenced in compose files as `${EXIST_PUID:-1000}:${EXIST_PGID:-1000}`), so files
written into bind-mounted volumes stay owned by — and deletable by — the user running the
stack. `existential.sh` auto-detects and writes them from `id -u` / `id -g` on the first
run. Override only if your containers must run as a different user than the one invoking
docker compose.

## Hostnames, DNS and TLS

`EXIST_LOCAL_HOST_IP`, `EXIST_DOMAIN`, `EXIST_PEER_HOST_IP` and `EXIST_PUBLIC_DOMAIN` are
covered end to end in [The Pieces → Hostnames that just
work](./how-it-works.md#hostnames-that-just-work). The short version:

- `EXIST_LOCAL_HOST_IP` is filled in automatically — the tailnet address when tailscale is
  up (`tailscale ip -4`), otherwise the LAN address the kernel would use to reach the
  internet. It must stay **above** `EXIST_DOMAIN` in the file: the `EXIST_NIP_DOMAIN`
  placeholder is derived from it, and placeholders resolve top-down.
- `EXIST_DOMAIN` defaults to `<your-ip-with-dashes>.nip.io`, public wildcard DNS that maps
  the name straight back to that IP — so `https://dashy.<domain>` works from any phone or
  laptop with no pihole and no `/etc/hosts`. With tailscale up, the name resolves publicly
  but only *routes* from inside your tailnet.
- **Never** set `EXIST_DOMAIN` to a MagicDNS name like `<node>.ts.net`. MagicDNS resolves
  exact node names only — there is no wildcard beneath one — so every `<slug>.` under it
  is NXDOMAIN.
- `EXIST_PEER_HOST_IP` is only for peer mode, where Caddy lives on a separate front-door
  host. Blank means single-host.
- `EXIST_PUBLIC_DOMAIN` adds real Let's Encrypt certs alongside the local hostnames. It
  requires that you own the domain, that `<domain>` and `*.<domain>` resolve to your
  public IP, and that ports 80 and 443 are forwarded to this machine. Run
  `./existential.sh run caddy public-domain` after changing it.

`EXIST_NETWORK_EXTERNAL` and `EXIST_DOCKER_NETWORK_SUBNET` describe the `exist` bridge
network — set the first to `true` only if you create the network yourself with
`docker network create`.

## Storage

Persistent data is host bind mounts, never Docker-managed volumes. Without an NFS host
mount, every volume lives under `<repo>/volumes/<name>`.

The NFS trio ships blank and **none of them is a first-run question** — a NAS is a thing
you either have or you don't. The NAS Storage quest (`./existential.sh quest`) walks
through mounting the export and filling them in, and you can run it at any time.

To do it by hand, mount the NFS export on the **host** (fstab/autofs), then point
`EXIST_NFS_HOST_MOUNT` at that mountpoint. `EXIST_NFS_SERVER_ADDRESS` and
`EXIST_NFS_BASE_PATH` only document where the export lives (the quest reads them); Docker
no longer mounts NFS itself.

`EXIST_BACKUP_RCLONE_REMOTE` is any rclone remote (`<remote>:<path>`), set by
`./existential.sh run backup-config`. Blank disables scheduled DB backups; volume backups
are invoked manually.

## Shared service credentials

The remaining keys are secrets shared *between* services, generated on render:

- `EXIST_HERMES_API_KEY` — the hermes gateway key, shared by hermes-agent and open-webui.
- `EXIST_NTFY_URL` / `EXIST_NTFY_TOKEN` — push notifications. The URL is container-to-container
  (Docker DNS); the token is generated by `./existential.sh run ntfy setup` after first boot.
- `EXIST_TELEGRAM_BOT_TOKEN` / `EXIST_TELEGRAM_CHAT_ID` — the fallback `notify.sh` uses when
  ntfy is unreachable. Create a bot with [BotFather](https://t.me/BotFather) (`/newbot`), then
  message it and read the chat ID from `https://api.telegram.org/bot<TOKEN>/getUpdates`.
- `EXIST_DECREE_MINIO_WEBHOOK_AUTH_TOKEN` — the bearer token minIO uses when posting to
  decree's `/minio` webhook endpoint.
- `EXIST_MINIO_NEXTCLOUD_ACCESS_KEY` / `EXIST_MINIO_NEXTCLOUD_SECRET_KEY` — the bucket-scoped
  MinIO identity Nextcloud mounts `/S3` with, created by minIO's
  `02-create-nextcloud-service-account` migration. Not the console login — see
  [MinIO](./storage/minio.md).
- `EXIST_MINIO_DOMAIN`, `EXIST_MINIO_SERVER_URL`, `EXIST_NEXTCLOUD_DOMAIN`,
  `EXIST_REDIS_PASSWORD` — see [Storage](./storage/index.md).
