---
service: ai/ollama
sidebar_position: 2
---

# Ollama

General AI model hosting. Everything else in the stack that reasons, embeds or reads an image
talks to it.

- Source: https://github.com/ollama/ollama
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: vLLM, LocalAI, LM Studio

## Models

You do not pick models here. Model choice is global and lives in the *Model Selection* block of
`.env.shared`, filled in from a VRAM tier table by the question asked the first time ollama is enabled — see
[Configuration → Models](../configuration#models).

The models are pulled for you: the `10-ollama-*` … `14-ollama-*` decree migrations run as soon as
ollama answers `/api/tags`, once the `local-models` flow is on (`./existential.sh flow on local-models`). Without it, pull manually:

```bash
./existential.sh run ollama pull-models
```

Migration `11` rebuilds the chat tag with `num_ctx=EXIST_MODEL_CHAT_NUM_CTX` (65536), because
ollama otherwise serves a much smaller default context and **truncates silently** — which reads
as the model forgetting its instructions rather than as an error. Hermes refuses to start below
64,000 tokens.

A running instance keeps the context it was loaded with, so after a rebuild evict it:

```bash
./existential.sh run ollama unload
```

## Where it runs

`EXIST_MODEL_URL` (and the per-role `EXIST_MODEL_URL_CHAT|_EXTRACT|_EMBED|_VISION`) decide which
machine serves each role, as OpenAI-compatible `/v1` URLs, so the models can live on a different
box — or a different server, such as llama.cpp — than the rest of the stack. Pulling, unloading
and the ollama probes run only while `EXIST_IS_AI_OLLAMA=true`. The `ollama.<domain>` Caddy
hostname is this machine's ollama container. Details:
[Configuration → Endpoints](../configuration#endpoints--putting-roles-on-different-machines).

For GPU setup, see [Proxmox GPU](../hosting/proxmox#gpu).

## Diagnostics

```bash
./existential.sh run ollama test        # reachability, model presence, num_ctx, KV headroom
./existential.sh run ollama benchmark   # decode speed as context grows
```

