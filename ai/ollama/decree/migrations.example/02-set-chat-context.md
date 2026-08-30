---
routine: ollama-pull
OLLAMA_ROLE: chat-ctx
---
Rebuild EXIST_MODEL_CHAT with num_ctx=EXIST_MODEL_CHAT_NUM_CTX.

Hermes requires 64,000 tokens of context for its system prompt (skills, memory
and tool definitions). Ollama's stock context (4096–8192) silently truncates
it, which looks like the model "forgetting" its instructions rather than like
an error — so every VRAM tier ships 65536 and this migration is what makes the
running model honour it.

The rebuilt model keeps the SAME tag, so every consumer still names one model.
Runs after migration 01 (the base tag must exist before /api/create can
reference it); the routine pulls it first if you run this one standalone.

Context costs VRAM — the KV cache grows with it — but 64k is hermes' floor, not
a dial, so every tier carries it. On a small card the cache spills into system
RAM and ollama offloads layers to the CPU: slower, still correct.
