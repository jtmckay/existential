---
name: Ollama Model Setup
tagline: Pull the models used by Hermes, Honcho, OpenViking, and Open WebUI
e2e: false
services:
  - var: EXIST_IS_AI_OLLAMA
    label: Ollama
  - var: EXIST_IS_AI_HONCHO
    label: Honcho
  - var: EXIST_IS_AI_OPENVIKING
    label: OpenViking
  - var: EXIST_IS_AI_HERMES
    label: Hermes
  - var: EXIST_IS_AI_OPEN_WEBUI
    label: Open WebUI
---

Copy migration files into services/decree/decree/migrations/, one per role
— only the roles the services you enabled actually need. After
`docker compose up -d`, the decree daemon waits for Ollama to be healthy,
then runs each migration once, in order — no further manual steps.

  mkdir -p services/decree/decree/migrations/

  # Always, if Ollama is enabled — the chat model and its context window
  cp services/decree/decree/migrations.example/10-ollama-pull-chat-model.md \
     services/decree/decree/migrations.example/11-ollama-set-chat-context.md \
     services/decree/decree/migrations/

  # Only if Honcho is enabled — the extraction model it uses for memory work
  cp services/decree/decree/migrations.example/12-ollama-pull-extract-model.md \
     services/decree/decree/migrations/

  # Only if OpenViking is enabled — the embedding model for its vector store
  cp services/decree/decree/migrations.example/13-ollama-pull-embed-model.md \
     services/decree/decree/migrations/

  # Always, if Ollama is enabled — skips itself at runtime if EXIST_MODEL_VISION is blank
  cp services/decree/decree/migrations.example/14-ollama-pull-vision-model.md \
     services/decree/decree/migrations/

  docker compose restart decree

These migrations do NOT name a model. They name a ROLE, and the routine
resolves it against the "Model Selection" block in .env.shared. Change a
model in that one place and everything downstream follows — honcho's config
is re-rendered from it, openviking's embedding settings come from it, and
hermes is pointed at it on first boot.

Roles:

  chat       EXIST_MODEL_CHAT — the agent's brain. Hermes uses it for every
             task, so it MUST support tool calling (look for the "tools"
             badge on its ollama.com page).

  chat-ctx   Rebuilds the chat model with num_ctx=EXIST_MODEL_CHAT_NUM_CTX,
             keeping the same tag. Hermes requires 64,000 tokens for its
             system prompt (skills + memory + tools), so every VRAM tier
             ships 65536; ollama's stock 4096–8192 truncates it silently,
             which reads as the model ignoring its instructions.

  extract    EXIST_MODEL_EXTRACT — Honcho's deriver (user representation),
             dialectic reasoning, and session summaries. Defaults to the same
             tag as chat so only one model stays resident on a small card.

  embed      EXIST_MODEL_EMBED — OpenViking's vector store.
             WARNING: do not change after first ingestion — mismatched
             dimensions will corrupt the vector index.

  vision     EXIST_MODEL_VISION — image OCR (ollama-ocr file processor) and
             image chat in Open WebUI. BLANK by default, and the migration
             the same tag as chat by default — every tier model is
             multimodal, so an image reuses what is already loaded instead of
             evicting it for a separate llava.

Pull times at the 8 GB default (first run, depending on connection speed):
  gemma4:e2b-it-qat   4.3 GB  5–12 min
  bge-m3              1.2 GB  1–3 min

Sizes for the other tiers are in src/utils/model-tiers.sh.

To pull them manually instead:
  ./existential.sh run ollama pull-models
