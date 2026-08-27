---
routine: ollama-pull
OLLAMA_ROLE: chat-ctx
---
Rebuild EXIST_MODEL_CHAT with num_ctx=EXIST_MODEL_CHAT_NUM_CTX.

Hermes sends a large system prompt (~18k tokens of skills + memory). Ollama's
stock context (4096–8192) silently truncates it, which looks like the model
"forgetting" its instructions rather than like an error.

The rebuilt model keeps the SAME tag, so every consumer still names one model.
Runs after migration 01 (the base tag must exist before /api/create can
reference it); the routine pulls it first if you run this one standalone.

Context costs VRAM — the KV cache grows with it, which is why num_ctx is part
of the VRAM tier rather than a knob of its own.
