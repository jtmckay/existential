---
routine: ollama-pull
OLLAMA_MODEL: qwen3:8b
---
Pull qwen3:8b. Used by LightRAG for entity and relationship extraction
during document ingestion (LLM_MODEL), and by Honcho for the deriver,
dialectic reasoning, and session summaries. A capable instruction-following
model at the 8B tier — faster than gemma4:26b for high-volume background tasks.
