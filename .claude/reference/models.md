# Models: selection, endpoints, VRAM tiers

Three separate things, one rule each in `CLAUDE.md`. This is the why.

## Model selection is global

Every model the stack uses is named once, in `.env.exist.shared`'s *Model Selection* block:
`EXIST_MODEL_CHAT`, `_CHAT_NUM_CTX`, `_EXTRACT`, `_EMBED`, `_EMBED_DIM`, `_VISION`, `_STT`,
`_STT_LANGUAGE`, `_TTS_VOICE`.

Consumers read those keys rather than naming a tag themselves:

- ollama migrations name an `OLLAMA_ROLE`, never a tag
- honcho renders its `config.toml` from them
- the wyoming services take them as compose env

A hardcoded model tag in a service is a second place to edit when the user changes machines or
tiers, and the tier table below can no longer keep the stack consistent.

## Model addresses are per-role, and OpenAI-compatible

`.env.exist.shared`'s *Model Endpoints* block gives each role its own key —
`EXIST_MODEL_URL_CHAT`, `_EXTRACT`, `_EMBED`, `_VISION` — each shipped **blank** and falling
back to `EXIST_MODEL_URL`. That blankness is the mechanism: leaving them empty means "one
server for everything", and filling one in moves that role to another machine. It is how VRAM
gets spread across hosts without touching a service.

Every value is an **OpenAI-compatible base URL ending `/v1`** (default
`http://ollama:11434/v1`). ollama and a llama.cpp server both answer it, so every caller that
sends a prompt speaks `/v1/chat/completions` (or `/v1/embeddings`) and nothing else. Only
ollama's own API — pulling, unloading, `/api/show`, `/api/ps`, its health probe — lives at the
root, and those steps run **only when `EXIST_IS_AI_OLLAMA=true`**; they get the root from
`ollama_root_for <role>`, never by editing a URL themselves.

The keys used to be `EXIST_OLLAMA_URL*`, holding ollama's root. `_reconcile_env_keys`
(`_renamed_value` in `src/templates.sh`) carries an old value across, `/v1` appended, when it
appends the new key to an existing `.env.shared`.

Because the fallback chain matters, **never read a role key directly and never write your own
fallback**. There are exactly three resolvers, one per context:

| context | how to resolve |
|---|---|
| host scripts | source `src/utils/model-endpoints.sh`, call `endpoint_for <role>` |
| rendered templates | write the bare token `EXIST_MODEL_URL_EMBED`; `src/templates.sh` resolves it before substitution |
| containers (decree) | compose passes the raw keys; source `automation/lib/model.sh`, call `model_url <role>` |

Roles share `ollama-pull`'s `OLLAMA_ROLE` vocabulary, so a model is pulled to the machine that
actually serves it. Adding a role means touching all three resolvers —
`src/test/unit/test-model-endpoints.sh` asserts they agree, so a half-done role fails the suite.

**A decree script reaches a model through `automation/lib/model.sh`** (`model_chat`,
`model_gate`), straight at the role's URL. hermes is optional: `hermes.sh`'s `hermes_chat` is
`model_chat` aimed at the gateway, for work that needs an agent with tools, and hermes itself is
configured with the chat URL. `src/test/unit/test-model-client.sh` runs every prompt path
against a stub that serves only `/v1`.

**STT/TTS get no endpoint keys.** The wyoming services are CPU-only, so there is no VRAM to
spread, and Home Assistant is told where they live in its own UI.

## Values come from the VRAM tier table

`src/utils/model-tiers.sh` holds the table. Quest asks how much VRAM the machine has on first
run (after the GPU vendor question, and only when the answer was not *No GPU*);
`./existential.sh run models` re-asks later.

The picker's last entry is **Custom**, which takes a model name instead of a VRAM number and
comes back as the token `custom:<tag>`. `model_tier_row` synthesises a row for it and
`model_tier_env` fills the same keys, so neither caller needs a second code path. Two
differences from a tier: the context is `MODEL_TIER_CUSTOM_CTX` (the 64k floor, because nothing
here knows what the model holds), and **`EXIST_VRAM_GB` is left untouched** — the custom answer
says nothing about the card, and `EXIST_GPU_VENDOR` is already answered by then. Nothing
validates the tag; only ollama can, and `run ollama pull-models` is where a bad one surfaces.

`.env.exist.shared` ships the **default tier's model values (8 GB)** but ships `EXIST_VRAM_GB`
**blank**. The blank is the record of not-yet-asked, and quest's picker fires only while it is
empty — shipping a value there makes the question unreachable forever. A unit test asserts both
that the shipped model values match the 8 GB tier and that `EXIST_VRAM_GB` is blank, so **edit
the table, not the individual defaults**.

Every tier tag must satisfy three constraints (a hand-typed **Custom** model is the user's
problem, not the table's — the same three still apply to it, and nothing checks them):

- **ollama's `tools` capability** — hermes cannot act without it.
- **multimodal** — so images reuse the already-resident model rather than loading a second one.
- **at least 64k context** — hermes requires 64,000 tokens and ollama truncates *silently*
  below it, which reads as the model ignoring instructions rather than as an error.

On the small tiers that KV cache spills into system RAM. That is a speed cost, not a correctness
one, so no tier is cut just to meet the floor.

The `0` tier is CPU-only, and `src/generate-compose.ts` keys its GPU-reservation strip off that
exact value — **do not renumber it**.
