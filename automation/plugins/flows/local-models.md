---
machine: plugin
automation: local-models
name: Local models
tagline: Ollama on this machine pulls the models your VRAM tier names, once, as soon as it is up
docs: /docs/ai/ollama
services:
  - EXIST_IS_AI_OLLAMA
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - ollama_pull
migrations:
  10-ollama-pull-chat-model: |
    ---
    machine: ollama_pull
    params:
      OLLAMA_ROLE: chat
    ---
    Pull the primary chat/reasoning model — whatever EXIST_MODEL_CHAT names in
    .env.shared. Used by pi, decree scripts and Open WebUI.

    The tag is NOT hardcoded here: the decree container receives the
    EXIST_MODEL_* globals and the ollama-pull routine resolves
    the role against them. Change the model in one place — the "Model Selection"
    block in .env.shared — and re-run this migration.

    Expect a few minutes on first pull — 4.3 GB at the 8 GB default tier. The tier
    table (src/utils/model-tiers.sh) sizes this so the chat model stays resident on the card
    you said you have on the first run.
  11-ollama-set-chat-context: |
    ---
    machine: ollama_pull
    params:
      OLLAMA_ROLE: chat-ctx
    ---
    Rebuild EXIST_MODEL_CHAT with num_ctx=EXIST_MODEL_CHAT_NUM_CTX.

    An agent's tool loop (pi's instructions, tool definitions and every tool result
    so far) needs 64,000 tokens of context. Ollama's stock context (4096–8192)
    silently truncates it, which looks like the model "forgetting" its instructions rather than like
    an error — so every VRAM tier ships 65536 and this migration is what makes the
    running model honour it.

    The rebuilt model keeps the SAME tag, so every consumer still names one model.
    Runs after migration 10 (the base tag must exist before /api/create can
    reference it); the routine pulls it first if you run this one standalone.

    Context costs VRAM — the KV cache grows with it — but 64k is the stack's floor, not
    a dial, so every tier carries it. On a small card the cache spills into system
    RAM and ollama offloads layers to the CPU: slower, still correct.
  14-ollama-pull-vision-model: |
    ---
    machine: ollama_pull
    params:
      OLLAMA_ROLE: vision
    ---
    Pull the vision model — EXIST_MODEL_VISION. Used by the ollama-ocr file
    processor (workspace/.decree/lib/file-processors.example/ollama-ocr.sh) for text
    extraction from images dropped into Nextcloud, and
    available in Open WebUI for image chat.

    EXIST_MODEL_VISION defaults to the SAME tag as EXIST_MODEL_CHAT: every tier
    model is multimodal, so an image reuses the model already resident instead of
    evicting it for a separate llava. This migration then finds it present and
    skips. Set it blank to turn image handling off entirely.
---

The models are named once, in .env.shared's Model Selection block; change them with
./existential.sh run models. To pull in the foreground instead:
  ./existential.sh run ollama pull-models
