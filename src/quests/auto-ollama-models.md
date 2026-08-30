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
copies:
  - src: ai/ollama/decree/migrations.example/01-pull-chat-model.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: pull the chat model (EXIST_MODEL_CHAT)"
    requires: EXIST_IS_AI_OLLAMA
  - src: ai/ollama/decree/migrations.example/02-set-chat-context.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: apply the chat context window (EXIST_MODEL_CHAT_NUM_CTX)"
    requires: EXIST_IS_AI_OLLAMA
  - src: ai/ollama/decree/migrations.example/03-pull-extract-model.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: pull the extraction model (EXIST_MODEL_EXTRACT)"
    requires: EXIST_IS_AI_HONCHO
  - src: ai/ollama/decree/migrations.example/04-pull-embed-model.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: pull the embedding model (EXIST_MODEL_EMBED)"
    requires: EXIST_IS_AI_OPENVIKING
  - src: ai/ollama/decree/migrations.example/05-pull-vision-model.md
    dst: ai/ollama/decree/migrations/
    label: "ollama: pull the vision model (skips when EXIST_MODEL_VISION is blank)"
    requires: EXIST_IS_AI_OLLAMA
---

Copies migration files into ai/ollama/decree/migrations/. After
docker compose up -d, ollama-decree waits for Ollama to be healthy,
then pulls each selected model in order — no manual steps.

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
