---
routine: ollama-pull
OLLAMA_MODEL: gemma4:26b
OLLAMA_FROM: gemma4:26b
OLLAMA_NUM_CTX: 65536
---
Apply extended context window to gemma4:26b via Modelfile.

Hermes loads a large system prompt (~18k tokens of skills + memory) and
LightRAG passes full graph context for synthesis. The default num_ctx
(4096–8192) silently truncates both. 65536 gives comfortable headroom.

Mirrors ai/ollama/Modelfile.exist.Modelfile. Must run after migration 01
(base model must be present before /api/create can reference it).
