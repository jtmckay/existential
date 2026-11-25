---
service: ai/strata
sidebar_position: 3
---

# Strata

An alternative to [Ollama](./ollama.md) for the chat role. It runs large mixture-of-experts
models that do not fit in VRAM. Shared layers, the context cache and the experts used most
stay on the GPU. The rest of the experts run on the CPU from RAM, and model files live on
the SSD.

- Source: https://github.com/Niko1221/Strata
- License: MIT (model weights carry their own licenses)
- Alternatives: Ollama, llama.cpp

## Before you turn it on

- **A GPU is required.** Strata publishes CUDA, ROCm and Intel images and no CPU image. The
  template uses `cuda13`, which needs driver 580 or newer. On a 575-579 driver, or a
  Pascal/Volta card, change the tag to `-cuda12`. On AMD it uses `rocm-gfx120x` (RX 9000). Change
  it to `rocm-gfx110x` for an RX 7000 or `rocm-gfx1151` for Strix Halo.
- **It needs the whole host.** The `qwen` packs need 38-55 GB of RAM plus VRAM, and the
  downloads are 66-76 GB. Size it against the RAM that is free while the rest of the stack
  runs, not the RAM installed. The container's limit is `96G`. A pack that needs more is
  killed while it loads, so raise the limit in `ai/strata/docker-compose.yml` first.
- **It replaces chat, not everything.** Embeddings, speech and image generation stay where they
  are.

## Turning it on

```bash
./existential.sh service on strata     # or EXIST_IS_AI_STRATA=true
```

Pick the pack in `ai/strata/.env` (`STRATA_FAMILY`, `STRATA_MODEL`), or leave both blank to
let Strata pick one for the card. The packs and their sizes are in
[upstream's model guide](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md).
`./existential.sh && docker compose up -d`, then watch the first download:

```bash
docker logs -f strata
```

Then point the stack at it in `.env.shared` and set the model names to the id Strata serves.
`./existential.sh run strata test` prints that id once the model is loaded.

```bash
EXIST_MODEL_URL=http://strata:8080/v1
EXIST_MODEL_CHAT=<id from the test>
EXIST_MODEL_VISION=<id from the test>      # vision is on, and the role follows chat
EXIST_IS_AI_OLLAMA=false                   # unless ollama still serves another role
```

`./existential.sh && docker compose up -d` again. Open WebUI keeps the backend it was first
rendered with ([Configuration → Endpoints](../configuration.md#endpoints)).

## The key

Strata refuses any request without its key. Its key is `EXIST_FLEET_SECRET`, which
`./existential.sh` generates in `.env.shared` and every model call already sends. Ollama
ignores the key, so the same key works with both servers.

## Context

`CONTEXT` is set from `EXIST_MODEL_CHAT_NUM_CTX` (65536), the stack's floor for an agent's tool
loop. Upstream's own compose file defaults to 32k.

## Diagnostics

```bash
./existential.sh run strata test   # /health, the key, and whether EXIST_MODEL_CHAT is served
```
