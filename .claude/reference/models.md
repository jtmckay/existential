# Models: selection, endpoints, VRAM tiers

Three separate things, one rule each in `CLAUDE.md`. This is the why.

## Model selection is global

Every model the stack uses is named once, in `.env.exist.shared`'s *Model Selection* block:
`EXIST_MODEL_CHAT`, `_CHAT_NUM_CTX`, `_VISION`, `_STT`,
`_STT_LANGUAGE`, `_TTS_VOICE`.

Consumers read those keys rather than naming a tag themselves:

- ollama migrations name an `OLLAMA_ROLE`, never a tag
- pi's provider is written from them (`lib/pi.sh`), open-webui's backend rendered from them
- the wyoming services take them as compose env

A hardcoded model tag in a service is a second place to edit when the user changes hosts or
tiers, and the tier table below can no longer keep the stack consistent.

## One model address, OpenAI-compatible; the fleet routes by model

`EXIST_MODEL_URL` is this host's model server, an **OpenAI-compatible base URL ending `/v1`**
(ships blank: no model yet, and `model_ready` is false; turning Ollama on fills
`http://ollama:11434/v1`, `_ollama_model_url` in `src/templates.sh`). A hosted LLM, ollama,
llama.cpp, Strata and the controller's `ai/model-gateway` all answer it, so every caller
that sends a prompt speaks `/v1/chat/completions` and nothing else. Only ollama's own API —
pulling, unloading, `/api/show`, `/api/ps`, its health probe — lives at the root (the URL less
`/v1`), and those steps run **only when `EXIST_IS_AI_OLLAMA=true`**.

Spreading models across hosts is the fleet's job, not an address's: in decree scripts, with
`EXIST_FLEET_SECRET` set, `model_base <role>` (lib/model.sh) asks the controller for the
service (`llm` or `strata`) whose offer lists the role's model (`EXIST_MODEL_CHAT`,
`EXIST_MODEL_VISION`), takes that host's lease, and falls back to `model_url`
(`EXIST_MODEL_URL`) when no host offers it. Apps that cannot lease (Home Assistant, Open WebUI,
opencode) read `EXIST_MODEL_URL`; pointing it at the controller's gateway
(`https://model-gateway.<controller's domain>/v1`) gives them the same leasing, since `gateway.ts` holds each call
under `fleet_use` / `fleet_done`. A blank `EXIST_MODEL_CHAT` is the first model the URL lists
(`model_first`, `/v1/models`).

**A decree script reaches a model through `lib/model.sh`** (`model_chat`,
`model_gate`), straight at the role's URL. Work that needs an agent with tools runs pi through
`pi.sh` (`pi_run`), whose provider `pi_configure` writes from `model_url` — the same
address, so pi cannot disagree with a script. `src/test/unit/test-model-client.sh` runs every prompt path
against a stub that serves only `/v1`.

**`EXIST_MODEL_KEY` for `EXIST_MODEL_URL`, `EXIST_FLEET_SECRET` for the fleet.** `model_key`
is `EXIST_MODEL_KEY` (a hosted LLM's API key), else the fleet secret, which the gateway and
Strata take; every model caller sends it (`model_chat`, `ocr.ts`, pi, opencode, Home Assistant).
A call under a fleet lease sends the fleet secret, the GPU host's key. `EXIST_FLEET_SECRET` is
generated and the same on every host, the bearer for leases (decree-go-rest). ollama ignores both.

**STT/TTS get no endpoint keys.** The wyoming services are CPU-only, so there is no VRAM to
spread, and Home Assistant is told where they live in its own UI.

## Values come from the VRAM tier table

`src/utils/model-tiers.sh` holds the table. The first run asks how much VRAM the machine has
(`src/lib/models.sh`), after the GPU vendor question and only when the answer was not *No GPU*;
`./existential.sh run models` re-asks later.

The picker's last entry is **Custom**, which takes a model name instead of a VRAM number and
comes back as the token `custom:<tag>`. `model_tier_row` synthesises a row for it and
`model_tier_env` fills the same keys, so neither caller needs a second code path. Two
differences from a tier: the context is `MODEL_TIER_CUSTOM_CTX` (the 64k floor, because nothing
here knows what the model holds), and **`EXIST_VRAM_GB` is left untouched** — the custom answer
says nothing about the card, and `EXIST_GPU_VENDOR` is already answered by then. Nothing
validates the tag; only ollama can, and `run ollama pull-models` is where a bad one surfaces.

`.env.exist.shared` ships **no model**: `EXIST_MODEL_CHAT`, `EXIST_MODEL_VISION`,
`EXIST_MODEL_URL`, `EXIST_GPU_VENDOR` and `EXIST_VRAM_GB` blank, and the rest of what a tier sets
(the context) at the **default tier's (8 GB)** values. The blank GPU answers are the record of
not-yet-asked, and the question comes only while they are empty. A unit test asserts both, so
**edit the table, not the individual defaults**.

Every tier tag must satisfy three constraints (a hand-typed **Custom** model is the user's
problem, not the table's — the same three still apply to it, and nothing checks them):

- **ollama's `tools` capability** — pi cannot act without it.
- **multimodal** — so images reuse the already-resident model rather than loading a second one.
- **at least 64k context** — an agent's tool loop needs 64,000 tokens and ollama truncates *silently*
  below it, which reads as the model ignoring instructions rather than as an error.

On the small tiers that KV cache spills into system RAM. That is a speed cost, not a correctness
one, so no tier is cut just to meet the floor.

The `0` tier is CPU-only, and `src/generate-compose.ts` keys its GPU-reservation strip off that
exact value — **do not renumber it**.
